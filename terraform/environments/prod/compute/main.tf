# Cluster EKS + node group gerenciado.
# Nenhum recurso Kubernetes e criado aqui (evita corrida de autenticacao);
# tudo dentro do cluster e entregue pelo ArgoCD (GitOps).

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "prod/networking/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  net = data.terraform_remote_state.networking.outputs
  # Sem NAT, os nodes precisam das subnets publicas (saida para internet).
  node_subnets = local.net.nat_enabled ? local.net.private_subnet_ids : local.net.public_subnet_ids
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  subnet_ids      = local.node_subnets
  instance_types  = var.instance_types
  capacity_type   = var.capacity_type
  desired_size    = var.desired_size
  min_size        = var.min_size
  max_size        = var.max_size
  propagate_tags  = local.finops_tags
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/${var.name}/prod/cluster-name"
  type  = "String"
  value = module.eks.cluster_name
  tags  = { Service = "platform-eks" }
}

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "desired_size" {
  type    = number
  default = 3
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}
