variable "bucket_name" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 90
}

variable "force_destroy" {
  description = "Permite destroy com objetos (ambiente academico)"
  type        = bool
  default     = true
}
