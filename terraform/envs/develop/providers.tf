provider "aws" {
  region  = "ap-northeast-2"
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "MoongCheap"
      ManagedBy   = "Terraform"
      Service     = "infra"
      Owner       = "cloud"
      Environment = "develop"
    }
  }
}

provider "cloudflare" {
  api_token = data.aws_secretsmanager_secret_version.cloudflare_api_token.secret_string
}