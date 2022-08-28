#State can be managed remotely using s3 bucket.
#terraform {
#   backend "s3" {
#     bucket       = "infra-automation-s3"
#     key          = "xyz.tfstate"
#     region       = "ap-south-1"
#     session_name = "terraform"
#   }
# }
provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project = "terraform-aws-autoscaling"
    }
  }
}