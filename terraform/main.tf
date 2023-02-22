########################################################
# Must Install the latest version of aws cli & terraform
########################################################
# https://karpenter.sh/v0.23.0/getting-started/getting-started-with-terraform/

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
        version = "4.55.0"
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
    bucket         = "cloudgeeksca-terraform"
    key            = "env/dev/cloudgeeks-dev.tfstate"
    region         = "us-east-1"
   # dynamodb_table = "cloudgeeksca-dev-terraform-backend-state-lock"
  }
}


locals {
  cluster_name = "cloudgeeks-eks-dev"
  cluster_version = "1.24"
}


#########
# Eks Vpc
#########
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source  = "registry.terraform.io/terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name            = local.cluster_name

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
    "kubernetes.io/cluster/${local.cluster_name}"  = "owned"
    "karpenter.sh/discovery/${local.cluster_name}" = local.cluster_name
    "kubernetes.io/role/internal-elb"              = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"       = "1"
  }

}




#############
# Eks Cluster
#############
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
module "eks" {
  source  = "registry.terraform.io/terraform-aws-modules/eks/aws"
  version = "19.10.0"

  cluster_name                    = local.cluster_name
  cluster_version                 = local.cluster_version
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = [module.vpc.private_subnets][0]
  enable_irsa                     = true
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
    aws-ebs-csi-driver = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "Egress Allowed 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
    ingress_nodes_karpenter_ports_tcp = {
      description                = "Karpenter required port"
      protocol                   = "tcp"
      from_port                  = 8443
      to_port                    = 8443
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {

    ingress_self_all = {
      description = "Self allow all ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    egress_all = {
      description      = "Egress allow all"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }



  }

  # Create, update, and delete timeout configurations for the cluster
  cluster_timeouts = {
    create = "60m"
    delete = "30m"
  }

  create_iam_role = true
  iam_role_name   = "eks-cluster-role"


  cluster_enabled_log_types = []

  create_cluster_security_group       = true
  create_node_security_group          = true
  node_security_group_use_name_prefix = false
  node_security_group_tags = {
    "karpenter.sh/discovery/${local.cluster_name}" = local.cluster_name
  }

  iam_role_additional_policies = {
    AmazonEKSVPCResourceController = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
    AmazonSSMManagedInstanceCore   =  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    AmazonEBSCSIDriverPolicy       = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

 # Sub Module

  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group

  eks_managed_node_groups = {
    on-demand = {
      min_size      = 2
      max_size      = 2
      desired_size  = 2
      update_config = {
        max_unavailable = 1
      }

      create_launch_template     = true
      instance_types             = ["t3a.medium"]
      capacity_type              = "ON_DEMAND"
      subnet_ids                 = [module.vpc.private_subnets][0]
      use_custom_launch_template = true
      enable_monitoring          = true
      ebs_optimized              = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs         = {
            volume_size           = 50
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      tags = {
        Environment = "dev"
        Terraform   = "true"
      }
      labels = {
        Environment                  = "dev"
        lifecycle                    = "Ec2OnDemand"
        "karpenter.sh/capacity-type" = "on-demand"
      }
    }



    spot = {
      min_size     = 0
      max_size     = 1
      desired_size = 0

      create_launch_template = true
      instance_types = ["t3a.medium"]
      capacity_type  = "SPOT"
      subnet_ids     = [module.vpc.private_subnets][0]
      use_custom_launch_template = true
      disk_type = "gp3"
      disk_encrypted  = true
      disk_size = 50
      update_config = {
        max_unavailable = 1
      }
      enable_monitoring = true
      ebs_optimized = true
      labels = {
        Environment                  = "dev"
        lifecycle                    = "Ec2Spot"
        "aws.amazon.com/spot"        = "true"
        "karpenter.sh/capacity-type" = "spot"
      }



      tags = {
        Environment = "dev"
        Terraform   = "true"
      }
    }


  }

  tags = {
    "karpenter.sh/discovery/${local.cluster_name}" = local.cluster_name
  }

}

