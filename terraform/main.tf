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

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.6.0"
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
#  backend "s3" {
#    bucket         = "cloudgeeksca-terraform"
#    key            = "env/dev/cloudgeeks-dev.tfstate"
#    region         = "us-east-1"
#   # dynamodb_table = "cloudgeeksca-dev-terraform-backend-state-lock"
#  }
#}


locals {
  cluster_name = "cloudgeeks-eks-dev"
  cluster_version = "1.25"
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
  database_subnets = ["10.60.11.0/24", "10.60.12.0/24", "10.60.13.0/24"]


  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

  create_database_subnet_group           = true
  database_subnet_group_name             = "cloudgeeks-eks-dev"
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

      iam_role_additional_policies = {
        AmazonEKSVPCResourceController = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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

      iam_role_additional_policies = {
        AmazonEKSVPCResourceController = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }


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


  manage_aws_auth_configmap = false
  aws_auth_roles = [
    {
      rolearn  = module.eks_admins_iam_role.iam_role_arn
      username = module.eks_admins_iam_role.iam_role_name
      groups   = ["system:masters"]
    },
  ]

}



######
# Mysql
#######
locals {
  name = "cloudgeeks-mysql"
  tags = {
    Name = local.name
  }
}



module "rds_mysql" {
  source  = "terraform-aws-modules/rds/aws//modules/db_instance"
  version = "5.6.0"

  identifier                                               = local.name
  final_snapshot_identifier_prefix                         = "mydb-final-snap-shot"
  allocated_storage                                        = "50"
  storage_type                                             = "gp2"
  engine                                                   = "mysql"
  engine_version                                           = "5.7.41"
  instance_class                                           = "db.t3.micro"
  backup_retention_period                                  = "1"
  backup_window                                            = "03:00-04:00"
  publicly_accessible                                      = false
  db_name                                                  = "cloudgeeks"
  username                                                 = "dbadmin"
  password                                                 = var.password
  vpc_security_group_ids                                   = [module.vpc.default_security_group_id,
                                                              module.eks.node_security_group_id]
  db_subnet_group_name                                     = module.vpc.database_subnet_group_name
  skip_final_snapshot                                      = true
  multi_az                                                 = false
  storage_encrypted                                        = true
  deletion_protection                                      = false
  performance_insights_enabled                             = false

  depends_on                                               = [module.vpc]
}


# Simple IAM Policy creation to allow EKS access
module "allow_eks_access_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "allow-eks-access"
  create_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# EKS Admin IAM Role
module "eks_admins_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "5.3.1"

  role_name         = "eks-admin"
  create_role       = true
  role_requires_mfa = false

  custom_role_policy_arns = [module.allow_eks_access_iam_policy.arn]

  trusted_role_arns = [
    "arn:aws:iam::${module.vpc.vpc_owner_id}:root"
  ]
}


# STS Policy to Assume EKS Admin IAM Role
module "allow_assume_eks_admins_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "allow-assume-eks-admin-iam-role"
  create_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = module.eks_admins_iam_role.iam_role_arn
      },
    ]
  })
}


# EKS Cluster Access IAM Group creation add users in this eks-admin group from AWS IAM Console
# Create IAM Group & attach STS Policy
module "eks_admins_iam_group" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version = "5.3.1"

  name                              = "eks-admin"
  attach_iam_self_management_policy = false
  create_group                      = true
  custom_group_policy_arns          = [module.allow_assume_eks_admins_iam_policy.arn]
}


