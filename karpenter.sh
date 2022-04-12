#!/bin/bash
# https://karpenter.sh/v0.8.2/getting-started/getting-started-with-eksctl/
# # https://karpenter.sh/v0.8.2/getting-started/migrating-from-cas/


export CLUSTER_NAME="cloudgeeks-eks-dev"
export REGION="us-east-1"
export VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region $REGION | awk '{print $5}' | grep -i vpc)
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/karpenter-controller-${CLUSTER_NAME}"
export KARPENTER_VERSION=v0.8.2


echo $VPC_ID
SECURITY_GROUPS=$(aws ec2 describe-security-groups --region $REGION --filter Name=vpc-id,Values=${VPC_ID} Name=group-name,Values=${CLUSTER_NAME}* --query 'SecurityGroups[*].[GroupId]' --output text)

export SECURITY_GROUPS
echo $SECURITY_GROUPS

aws ec2 create-tags \
    --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
    --resources ${SECURITY_GROUPS}


echo $CLUSTER_NAME
echo $CLUSTER_ENDPOINT
echo $KARPENTER_IAM_ROLE_ARN
echo $KARPENTER_VERSION

helm repo add karpenter https://charts.karpenter.sh/
helm repo update
helm upgrade --install --namespace karpenter --create-namespace \
  karpenter karpenter/karpenter \
  --version ${KARPENTER_VERSION} \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_IAM_ROLE_ARN} \
  --set clusterName=${CLUSTER_NAME} \
  --set clusterEndpoint=${CLUSTER_ENDPOINT} \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --wait # for the defaulting webhook to install before creating a Provisioner

 # End 

