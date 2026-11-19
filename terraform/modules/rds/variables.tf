variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas"
  type        = list(string)
}

variable "databases" {
  description = "Bancos por servico (metadados nao sensiveis, usados no for_each)"
  type = map(object({
    db_name             = string
    service             = string
    data_classification = string
  }))
}

variable "credentials" {
  description = "Usuario/senha por banco (mesmas chaves de databases)"
  type = map(object({
    username = string
    password = string
  }))
  sensitive = true
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling (0 desliga)"
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Multi-AZ dobra o custo; recomendado para donation em producao real"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de backup automatico (habilita PITR, RPO ~5 min)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
