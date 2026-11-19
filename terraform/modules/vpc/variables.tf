variable "name" {
  description = "Prefixo dos recursos de rede"
  type        = string
}

variable "region" {
  description = "Regiao AWS (para os VPC endpoints)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS (tags de descoberta de subnets)"
  type        = string
}

variable "cidr_block" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Quantidade de AZs"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway (custo ~US$ 33/mes). Desligado por padrao (FinOps)."
  type        = bool
  default     = false
}
