# Camada de dados: RDS (ngo, donation), DynamoDB (volunteer), SQS (eventos).
# Depende de: networking (VPC/subnets) e security (credenciais no SSM).

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "prod/networking/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_ssm_parameter" "db_credentials" {
  for_each = toset(["ngo", "donation"])
  name     = "/${var.name}/prod/${each.key}/db-credentials"
}

locals {
  net   = data.terraform_remote_state.networking.outputs
  creds = { for k, v in data.aws_ssm_parameter.db_credentials : k => jsondecode(v.value) }

  # Metadados nao sensiveis (podem ser usados em for_each).
  databases = {
    ngo = {
      db_name             = "ngo_db"
      service             = "ngo-service"
      data_classification = "internal"
    }
    donation = {
      db_name             = "donation_db"
      service             = "donation-service"
      data_classification = "critical" # caminho critico (hot path)
    }
  }
}

module "rds" {
  source = "../../../modules/rds"

  name                    = var.name
  vpc_id                  = local.net.vpc_id
  vpc_cidr_block          = local.net.vpc_cidr_block
  subnet_ids              = local.net.private_subnet_ids
  databases               = local.databases
  credentials             = local.creds
  instance_class          = var.rds_instance_class
  backup_retention_period = var.rds_backup_retention_days
}

module "dynamodb" {
  source     = "../../../modules/dynamodb"
  table_name = "SolidaryTechVolunteers"
}

module "sqs" {
  source     = "../../../modules/sqs"
  queue_name = "solidary-donations"
}

# Dados de conexao completos no SSM -> External Secrets monta DATABASE_URL.
resource "aws_ssm_parameter" "db_connection" {
  for_each = local.databases

  name = "/${var.name}/prod/${each.key}/db-connection"
  type = "SecureString"
  value = jsonencode({
    host     = module.rds.endpoints[each.key]
    port     = 5432
    dbname   = each.value.db_name
    username = local.creds[each.key].username
    password = local.creds[each.key].password
    # sslmode=require: o parameter group forca TLS (rds.force_ssl=1).
    url = "postgres://${local.creds[each.key].username}:${local.creds[each.key].password}@${module.rds.endpoints[each.key]}:5432/${each.value.db_name}?sslmode=require"
  })
  tags = { Service = each.value.service }
}

# Configuracao nao sensivel consumida pelos pods (via External Secrets).
resource "aws_ssm_parameter" "app_config" {
  name = "/${var.name}/prod/config/app"
  type = "String"
  value = jsonencode({
    AWS_REGION             = var.aws_region
    AWS_SQS_URL            = module.sqs.queue_url
    AWS_DYNAMODB_TABLE     = module.dynamodb.table_name
    AWS_DYNAMODB_NGO_INDEX = module.dynamodb.ngo_index_name
  })
  tags = { Service = "platform" }
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_backup_retention_days" {
  type    = number
  default = 1
}

output "rds_endpoints" {
  value = module.rds.endpoints
}

output "rds_identifiers" {
  value = module.rds.identifiers
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}
