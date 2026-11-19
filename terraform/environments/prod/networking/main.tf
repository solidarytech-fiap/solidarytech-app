module "vpc" {
  source = "../../../modules/vpc"

  name               = var.name
  region             = var.aws_region
  cluster_name       = var.cluster_name
  cidr_block         = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = var.enable_nat_gateway
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "nat_enabled" {
  value = module.vpc.nat_enabled
}
