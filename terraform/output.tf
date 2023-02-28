output "vpc" {
  value = module.vpc
}

output "eks" {
  value = module.eks
}

output "rds_mysql" {
  value = module.rds_mysql
  sensitive = true
}