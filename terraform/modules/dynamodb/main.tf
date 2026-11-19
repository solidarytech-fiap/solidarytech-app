# Tabela de voluntarios. On-Demand (PAY_PER_REQUEST): sem custo ocioso,
# absorve os picos imprevisiveis citados pela diretoria.
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  attribute {
    name = "ngo_id"
    type = "N"
  }

  # GSI para consultar voluntarios por ONG sem Scan (custo e latencia).
  global_secondary_index {
    name            = var.ngo_index_name
    hash_key        = "ngo_id"
    projection_type = "ALL"
  }

  # PITR: restauracao para qualquer segundo dos ultimos 35 dias (DR).
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.deletion_protection

  tags = {
    Name    = var.table_name
    Service = "volunteer-service"
  }
}
