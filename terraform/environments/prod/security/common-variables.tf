variable "aws_region" {
  description = "Regiao primaria"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Regiao de Disaster Recovery"
  type        = string
  default     = "us-west-2"
}

variable "tf_state_bucket" {
  description = "Bucket S3 do state (leitura de remote state entre camadas)"
  type        = string
}

variable "name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "solidarytech"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
  default     = "solidarytech-eks"
}
