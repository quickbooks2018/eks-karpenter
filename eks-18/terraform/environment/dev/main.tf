terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    #  version = "4.7.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = "~> 1.0"
}


### Backend ###
# S3
###############

#terraform {
#backend "s3" {
#  bucket         = "cloudgeeks-eks-terraform"
#   key            = "env/dev/cloudgeeks-eks-dev.tfstate"
#   region         = "us-east-1"
#
#  }
#}


#########
# Eks Vpc
#########
module "eks_vpc" {
  source  = "registry.terraform.io/terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name            = var.cluster_name

  cidr            = "10.60.0.0/16"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.60.0.0/23", "10.60.2.0/23", "10.60.4.0/23"]
  public_subnets  = ["10.60.100.0/23", "10.60.102.0/24", "10.60.104.0/24"]


  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
    "kubernetes.io/role/internal-elb"           = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"       = "1"
  }


}



#############
# Eks Cluster
#############
module "eks" {
  source  = "registry.terraform.io/terraform-aws-modules/eks/aws"
  version = "18.21.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.21"

  vpc_id     = module.eks_vpc.vpc_id
  subnet_ids = module.eks_vpc.private_subnets

  enable_irsa = true

  create_cluster_security_group = false
  create_node_security_group    = false

  eks_managed_node_groups = {
    workers = {

      create_launch_template = true
      name                   = "cloudgeeks-eks-workers"  # Eks Workers Node Groups Name
      instance_types         = ["t3a.medium"]
      capacity_type          = "ON_DEMAND"
      ebs_optimized          = true
      key_name               = "cloudgeeks-eks"
      enable_monitoring      = true

      min_size     = 1
      max_size     = 1
      desired_size = 1

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
           # kms_key_id            = aws_kms_key.ebs.arn
            delete_on_termination = true
          }
        }
      }


      iam_role_additional_policies = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]
    }
  }

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

############################
# Karpenter Service Account (Karpenter requires permissions like launching instances, which means it needs an IAM role that grants it access)
############################
module "karpenter_irsa" {
  source  = "registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.0.0"

  role_name                          = "karpenter-controller-${var.cluster_name}"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id    = module.eks.cluster_id
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["workers"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

########################
# KarpenterNode IAM Role  # reference in karpenter installation (so we don’t have to reconfigure the aws-auth ConfigMap)
#########################
module "karpenter_node_iam_role" {
  source = "../../modules/eks-karpenter-node-iam-role"
  instance_profile_name        = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  worker_iam_role_name         = module.eks.eks_managed_node_groups["workers"].iam_role_name
}

########################
# Karpenter installation
########################
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

module "karpernter_installation" {
  source = "../../modules/eks-karpenter-installation"
  cluster_endpoint                          = module.eks.cluster_endpoint
  cluster_name                              = var.cluster_name
  instance_profile                          = module.karpenter_node_iam_role.aws_iam_instance_profile_karpenter_name
  iam_assumable_role_karpenter_iam_role_arn = module.karpenter_irsa.iam_role_arn
  depends_on                                = [module.eks.eks_managed_node_groups]
  karpenter_version                         = "v0.10.0"
}
