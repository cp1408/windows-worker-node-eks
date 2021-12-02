terraform {
  backend "s3" {
    bucket         = "terraform-automation-s3-backend"
    key            = "terraform-poc-eks-dev/windows-worker-node.tfstate"
    dynamodb_table = "eks-cluster-version-locking"
    region         = "us-west-2"
  }
}