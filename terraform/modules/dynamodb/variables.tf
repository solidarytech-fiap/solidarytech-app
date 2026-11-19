variable "table_name" {
  type = string
}

variable "ngo_index_name" {
  type    = string
  default = "ngo_id-index"
}

variable "deletion_protection" {
  type    = bool
  default = false
}
