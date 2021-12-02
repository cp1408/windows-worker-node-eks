provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "aws" {
  region  = var.region
  version = "~> 3.55.0"
}
