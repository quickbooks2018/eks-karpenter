resource "aws_iam_instance_profile" "karpenter" {
  name = var.instance_profile_name
  role = var.worker_iam_role_name
}