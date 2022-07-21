terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.7.0"
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

terraform {
  backend "s3" {
    bucket         = "cloudgeeks-terraform"
    key            = "env/dev/cloudgeeks-dev.tfstate"
    region         = "us-east-1"
   # dynamodb_table = "cloudgeeks-dev-terraform-backend-state-lock"
  }
}

#  Error: configmaps "aws-auth" already exists
#  Solution: kubectl delete configmap aws-auth -n kube-system

#########
# Eks Vpc
#########
module "eks_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
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

# https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
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
  source  = "terraform-aws-modules/eks/aws"
  version = "17.24.0"

  cluster_version           = "1.21"
  cluster_name              = "cloudgeeks-eks-dev"
  vpc_id                    = module.eks_vpc.vpc_id
  subnets                   = module.eks_vpc.private_subnets
  workers_role_name         = "iam-eks-workers-role"
  create_eks                = true
  manage_aws_auth           = true
  write_kubeconfig          = true
  kubeconfig_output_path    = "/root/.kube/config" # touch /root/.kube/config   # for terraform HELM provider, we neeed this + #  Error: configmaps "aws-auth" already exists 
  kubeconfig_name           = "config"                                                                                         #  Solution: kubectl delete configmap aws-auth -n kube-system
  enable_irsa               = true                 # oidc
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/17.21.0/submodules/node_groups
  node_groups = {
    cloudgeeks-eks-workers = {
      create_launch_template = true
      name                   = "cloudgeeks-eks-workers"  # Eks Workers Node Groups Name
      instance_types         = ["t3a.medium"]
      capacity_type          = "ON_DEMAND"
      desired_capacity       = 1
      max_capacity           = 1
      min_capacity           = 1
      disk_type              = "gp2"
      disk_size              = 20
      ebs_optimized          = true
      disk_encrypted         = true
      key_name               = "terraform-cloudgeeks"
      enable_monitoring      = true

      additional_tags = {
        "Name"                     = "eks-worker"                            # Tags for Cluster Worker Nodes
        "karpenter.sh/discovery"   = var.cluster_name
      }

    }
  }


}


data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

###################################################
# EKS Cluster Auto-Scaling Karpenter Node IAM Role
###################################################
module "karpenter_node_iam_role" {
  source = "../../modules/eks-karpenter-node-iam-role"
  cluster_name                =  var.cluster_name
  ssm_managed_instance_policy =  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  worker_iam_role_name        =  module.eks.worker_iam_role_name
}

##############################
# KarpenterController IAM Role
##############################
module "karpenter_controller_iam_role" {
  source = "../../modules/eks-karpenter-controller-iam-role"
  cluster_name            = var.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
}

########################
# Karpenter installation
########################
module "karpernter_installation" {
  source = "../../modules/eks-karpenter-installation"
  cluster_endpoint                          = module.eks.cluster_endpoint
  cluster_name                              = var.cluster_name
  instance_profile                          = module.eks.worker_iam_role_name
  iam_assumable_role_karpenter_iam_role_arn = module.karpenter_controller_iam_role.iam_assumable_role_karpenter_iam_role_arn
  kubeconfig                                = module.eks.kubeconfig
  depends_on                                = [module.eks.kubeconfig]
  cluster_ca_certificate                    = base64decode(module.eks.cluster_certificate_authority_data)
  karpenter_version                         = "v0.5.3"
}
