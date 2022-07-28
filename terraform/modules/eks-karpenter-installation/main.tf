locals {
  cluster_name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = var.cluster_ca_certificate
    
# aws eks get-token --cluster-name cloudgeeks-eks-dev | jq '.apiVersion'    # Note: Install the lastest version of terraform & awscli is must 
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

resource "helm_release" "karpenter" {
  depends_on       = [var.kubeconfig]
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = var.karpenter_version
  verify     = false

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.iam_assumable_role_karpenter_iam_role_arn
  }

  set {
    name  = "controller.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "controller.clusterEndpoint"
    value = var.cluster_endpoint
  }
  
    set {
    name  = "aws.defaultInstanceProfile"
    value = var.instance_profile
  }
  
}
