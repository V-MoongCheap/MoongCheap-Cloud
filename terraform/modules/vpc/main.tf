# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.env}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.env}-igw"
  }
}

# Public Subnet (NAT Instance 배치용)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.env}-public-${var.azs[count.index]}"
  }
}

# WEB Private Subnet (FE Worker Node Group 배치용)
resource "aws_subnet" "web_private" {
  count             = length(var.web_private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.web_private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.env}-web-${var.azs[count.index]}"
  }
}

# WAS Private Subnet (BE·AI Worker Node Group 배치용)
resource "aws_subnet" "was_private" {
  count             = length(var.was_private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.was_private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.env}-was-${var.azs[count.index]}"
  }
}

# DB Private Subnet (RDS 배치용 — 인터넷 아웃바운드 라우트 없음)
resource "aws_subnet" "db_private" {
  count             = length(var.db_private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.db_private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.env}-db-${var.azs[count.index]}"
  }
}

# Public Route Table -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-${var.env}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# WEB/WAS Private Route Table — NAT로 가는 0.0.0.0/0 라우트는 여기서 넣지 않는다.
# NAT는 이제 별도 modules/nat에 있어서, 이 모듈이 직접 참조하면 nat 모듈은 vpc의
# public_subnet_id를, vpc 모듈은 nat의 network_interface_id를 필요로 하는 순환
# 의존이 생긴다. 그래서 Route Table(빈 테이블)까지만 여기서 만들고, 실제 NAT행
# aws_route는 두 모듈이 다 끝난 뒤 root(envs/*)에서 연결한다.
# 아키텍처 설계서_V2 3.1: WEB/WAS 모두 NAT Instance를 통해 인터넷 아웃바운드.
resource "aws_route_table" "web_private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.env}-web-rt"
  }
}

resource "aws_route_table_association" "web_private" {
  count          = length(aws_subnet.web_private)
  subnet_id      = aws_subnet.web_private[count.index].id
  route_table_id = aws_route_table.web_private.id
}

resource "aws_route_table" "was_private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.env}-was-rt"
  }
}

resource "aws_route_table_association" "was_private" {
  count          = length(aws_subnet.was_private)
  subnet_id      = aws_subnet.was_private[count.index].id
  route_table_id = aws_route_table.was_private.id
}

# DB Private Route Table -> 인터넷 목적지 라우트 없음 (아키텍처 설계서_V2 3.1)
# VPC 내부 통신(RDS <- BE/AI)은 각 Route Table에 자동 추가되는 local 라우트로 처리된다.
resource "aws_route_table" "db_private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.env}-db-rt"
  }
}

resource "aws_route_table_association" "db_private" {
  count          = length(aws_subnet.db_private)
  subnet_id      = aws_subnet.db_private[count.index].id
  route_table_id = aws_route_table.db_private.id
}
