# Plataforma: registries ECR e bucket de backup/DR na regiao secundaria.

data "aws_caller_identity" "current" {}

# Provider da regiao de DR com as mesmas tags FinOps.
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = merge(local.finops_tags, { DRRole = "secondary" })
  }
}

module "ecr" {
  source       = "../../../modules/ecr"
  repositories = ["ngo-service", "donation-service", "volunteer-service"]
}

module "backup_bucket" {
  source    = "../../../modules/s3-backup"
  providers = { aws = aws.dr }

  bucket_name = "${var.name}-dr-backups-${data.aws_caller_identity.current.account_id}"
}

# DR: replica todas as imagens para a regiao secundaria. Se us-east-1 cair,
# um cluster em us-west-2 consegue puxar as mesmas imagens (tag = SHA).
resource "aws_ecr_replication_configuration" "dr" {
  count = var.enable_ecr_replication ? 1 : 0

  replication_configuration {
    rule {
      # Sem repository_filter: replica todos os repositorios da conta.
      destination {
        region      = var.dr_region
        registry_id = data.aws_caller_identity.current.account_id
      }
    }
  }
}

variable "enable_ecr_replication" {
  description = "Replica imagens ECR para a regiao de DR (desligue se o Academy negar)"
  type        = bool
  default     = true
}

resource "aws_ssm_parameter" "dr_config" {
  name = "/${var.name}/prod/config/dr"
  type = "String"
  value = jsonencode({
    BACKUP_BUCKET = module.backup_bucket.bucket_name
    BACKUP_REGION = var.dr_region
  })
  tags = { Service = "disaster-recovery" }
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "backup_bucket" {
  value = module.backup_bucket.bucket_name
}

output "backup_bucket_region" {
  value = var.dr_region
}
