terraform {
  backend "s3" {
    bucket       = "moongcheap-tfstate"
    key          = "develop/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
    profile      = "moongcheap"
  }
}