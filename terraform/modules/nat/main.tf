# NAT Instance용 최신 Amazon Linux 2023 AMI 조회
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# NAT Instance용 보안 그룹 (VPC 내부 트래픽만 허용)
resource "aws_security_group" "nat" {
  name        = "${var.project}-${var.env}-nat-sg"
  description = "NAT Instance - allow traffic from within VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all traffic from within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-nat-sg"
  }
}

# 디버깅용 SSM 접속 (var.nat_enable_ssm = true일 때만 생성, 기본은 안 만듦)
data "aws_iam_policy_document" "nat_assume_role" {
  count = var.nat_enable_ssm ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nat_ssm" {
  count              = var.nat_enable_ssm ? 1 : 0
  name               = "${var.project}-${var.env}-nat-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.nat_assume_role[0].json
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  count      = var.nat_enable_ssm ? 1 : 0
  role       = aws_iam_role.nat_ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat_ssm" {
  count = var.nat_enable_ssm ? 1 : 0
  name  = "${var.project}-${var.env}-nat-ssm-profile"
  role  = aws_iam_role.nat_ssm[0].name
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.env}-nat-eip"
  }
}

# NAT Instance와 분리된 독립 ENI
# 인스턴스가 replace(재생성)되어도 이 ENI(및 여기 붙은 EIP/Route)는 그대로 유지되도록 하기 위함
resource "aws_network_interface" "nat" {
  subnet_id         = var.public_subnet_id
  private_ips       = [cidrhost(var.public_subnet_cidr, 10)]
  security_groups   = [aws_security_group.nat.id]
  source_dest_check = false

  tags = {
    Name = "${var.project}-${var.env}-nat-eni"
  }
}

# NAT Instance (NAT Gateway 대신 EC2 사용 - 비용 절감 목적)
# Tailscale Subnet Router 설정은 Ansible이 별도로 담당하지만, IP Forwarding + MASQUERADE(기본 NAT 동작
# 자체)는 이게 없으면 Private Subnet이 인터넷을 전혀 못 나가서 최소한으로 여기서 처리한다.
resource "aws_instance" "nat" {
  ami                  = data.aws_ami.al2023.id
  instance_type        = var.nat_instance_type
  iam_instance_profile = var.nat_enable_ssm ? aws_iam_instance_profile.nat_ssm[0].name : null

  network_interface {
    network_interface_id  = aws_network_interface.nat.id
    device_index          = 0
    delete_on_termination = false
  }

  # 실행 로그를 시리얼 콘솔로도 내보내서 `aws ec2 get-console-output`으로 성공 여부를 확인할 수 있게 한다.
  # (SSH/SSM 없이도 NAT 설정이 실제로 적용됐는지 검증하기 위함)
  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/nat-setup.log > /dev/console) 2>&1
    set -x

    # 1. IP Forwarding 활성화
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf

    # 2. AL2023에는 iptables가 기본 설치되어 있지 않으므로 직접 설치한다.
    #    이게 없으면 아래 규칙들이 전부 command not found로 실패한다.
    dnf install -y iptables-services
    systemctl enable iptables
    systemctl start iptables

    # 3. FORWARD 체인 허용 — MASQUERADE만 넣으면 filter 테이블에서 패킷이 DROP되어
    #    NAT가 동작하지 않는다. NAT Instance 구성에서 가장 흔히 빠뜨리는 부분.
    iptables -P FORWARD ACCEPT
    iptables -I FORWARD -j ACCEPT

    # 4. VPC 대역에서 나가는 트래픽을 마스커레이딩 (인터페이스명 의존 없이 소스 기준으로 지정)
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE

    # 5. TCP MSS Clamping — MTU 불일치로 HTTPS 연결이 멈추는 현상 방지
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    # 6. 재부팅 후에도 규칙이 유지되도록 저장
    iptables-save > /etc/sysconfig/iptables

    iptables -t nat -L -n -v
    iptables -L FORWARD -n -v
    echo "===== NAT SETUP COMPLETE ====="
  EOF

  # user_data는 첫 부팅 시에만 실행되므로, 바뀌면 인스턴스를 교체해야 실제로 반영된다.
  user_data_replace_on_change = true

  # AMI most_recent 갱신으로 인한 의도치 않은 재생성을 방지 (필요 시 수동으로 AMI 교체)
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.project}-${var.env}-nat"
  }
}

resource "aws_eip_association" "nat" {
  network_interface_id = aws_network_interface.nat.id
  allocation_id        = aws_eip.nat.id
}
