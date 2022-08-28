locals {
  name             = "all-components"
  cluster_version = "1.22"
  region           = "ap-south-1"
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}


################################################################################
# VPC and SGs
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name = local.name
  cidr = "20.10.0.0/16"

  azs             = ["${local.region}a", "${local.region}b"]
  private_subnets     = ["20.10.1.0/24", "20.10.2.0/24"]
  public_subnets      = ["20.10.11.0/24", "20.10.12.0/24"]
  database_subnets    = ["20.10.21.0/24", "20.10.22.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true
  create_database_subnet_group  = true
  create_database_subnet_route_table = true
  # for one natgw per az
  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true
  #manage_default_network_acl = true
  #default_network_acl_tags   = { Name = "${local.name}-default" }
  manage_default_route_table = true
  default_route_table_tags   = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }
  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
    public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}


################################################################################
# EKS
################################################################################

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  cluster_name                    = local.name
  cluster_version                 = local.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    example = {
      desired_size = 1

      instance_types = ["t3.large"]
      labels = {
        Task    = "managed_node_groups"
      }
      tags = {
        ExtraTag = "assignment"
      }
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "backend"
          labels = {
            Application = "backend"
          }
        },
        {
          namespace = "default"
          labels = {
            WorkerType = "fargate"
          }
        }
      ]

      tags = {
        Owner = "default"
      }

      timeouts = {
        create = "20m"
        delete = "20m"
      }
    }

    secondary = {
      name = "secondary"
      selectors = [
        {
          namespace = "default"
          labels = {
            Environment = "test"
          }
        }
      ]

      # Using specific subnets instead of the subnets supplied for the cluster itself
      subnet_ids = [module.vpc.private_subnets[1]]

      tags = {
        Owner = "secondary"
      }
    }
  }

  tags = local.tags
}

################################################################################
# s3 and SFTP
################################################################################

module "s3_bucket" {
  source  = "clouddrove/s3/aws"

  name        = "shinjani-ftp-bucket"
  environment = "dev"
  label_order = ["environment", "name"]

  versioning    = true
  acl           = "private"
  force_destroy = true
}

module "sftp" {
 source                    = "clouddrove/sftp/aws"
 version                   = "0.15.0"
 name                      = "sftp"
 environment               = "dev"
 key_path                  = "/path/sftp.pub"
 label_order               = ["name", "environment"]
 user_name                 = "ftp-user"
 enable_sftp               = true
 s3_bucket_id              = module.s3_bucket.id
 endpoint_type             = "PUBLIC"
 managedby                 = "shinjani"
        }