variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "iam_role_name" {
  description = "Role IAM existente (AWS Academy: LabRole)"
  type        = string
  default     = "LabRole"
}

variable "subnet_ids" {
  type = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs que acessam o endpoint publico da API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch (ajuda MTTR)."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "capacity_type" {
  description = "ON_DEMAND ou SPOT (SPOT ~60-70% mais barato)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type deve ser ON_DEMAND ou SPOT."
  }
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

variable "node_disk_size" {
  type    = number
  default = 20
}

variable "propagate_tags" {
  description = "Tags FinOps aplicadas nas instancias/volumes via launch template"
  type        = map(string)
}
