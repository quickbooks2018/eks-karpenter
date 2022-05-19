output "aws_iam_role_policy_karpenter_contoller" {
  value = aws_iam_role_policy.karpenter_contoller
}

output "iam_assumable_role_karpenter_iam_role_arn" {
  value = module.iam_assumable_role_karpenter.iam_role_arn
}