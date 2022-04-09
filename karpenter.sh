#!/bin/bash
# https://cmp307.ec2spotworkshops.com/040_karpenter/install_karpenter.html
# https://karpenter.sh/v0.8.1/getting-started/getting-started-with-eksctl/


export CLUSTER_NAME="cloudgeeks-eks-dev"
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"
export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::966399774209:role/karpenter-controller-cloudgeeks-eks-dev"

echo $CLUSTER_NAME
echo $CLUSTER_ENDPOINT
echo $KARPENTER_IAM_ROLE_ARN

helm repo add karpenter https://charts.karpenter.sh
helm repo update
helm upgrade --install karpenter karpenter/karpenter --namespace karpenter \
  --create-namespace --version 0.8.1 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_IAM_ROLE_ARN} \
  --set clusterName=${CLUSTER_NAME} \
  --set clusterEndpoint=${CLUSTER_ENDPOINT} \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --wait # for the defaulting webhook to install before creating a Provisioner


 # End 

