#!/bin/bash

if [ -d /root/.kube ]
then
echo "/root/.kube exists"
> /root/.kube/config

else
mkdir -p /root/.kube
touch /root/.kube/config
fi

if [ -d /root/.ssh ]
then
echo "/root/.ssh exists"
else
mkdir -p /root/.ssh
fi

if [ -f /root/.ssh/*.pem ]
then
echo "pem is there, I am removing it"
rm -f ~/.ssh/*.pem
export SSH_KEY_NAME="cloudgeeks-eks"
aws ec2 create-key-pair --key-name "${SSH_KEY_NAME}" --query 'KeyMaterial' --output text > ~/.ssh/${SSH_KEY_NAME}.pem
else
echo "All is well, now I am creating fresh PEM"
export SSH_KEY_NAME="cloudgeeks-eks"
aws ec2 create-key-pair --key-name "${SSH_KEY_NAME}" --query 'KeyMaterial' --output text > ~/.ssh/${SSH_KEY_NAME}.pem
fi

#End
