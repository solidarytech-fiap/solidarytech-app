variable "queue_name" {
  type = string
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 dias
}
