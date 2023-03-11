
# Policy
module "external-dns-policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.10.0"

  create_policy = true
  description   = "Allow access to external-dns route53"
  name          = "AllowExternalDNSUpdates"
  path          = "/"
  policy        = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

}

# Role
module "iam-assumable-role-with-oidc-just-like-iam-role-attachment-to-ec2" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.10.0"

  create_role      = true
  role_name        = "cloudgeeks-dev"
  provider_url     = module.eks.cluster_oidc_issuer_url
  role_policy_arns = [
    module.external-dns-policy.arn
  ]

}
