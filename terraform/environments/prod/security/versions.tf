terraform {
  required_version = ">= 1.10"

  # Backend parcial: bucket/region injetados no init
  #   terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=us-east-1"
  # use_lockfile: lock nativo do S3 (sem tabela DynamoDB).
  backend "s3" {
    key          = "prod/security/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ------------------------------------------------------------------
# FinOps - politica de tags obrigatorias.
# default_tags aplica em TODOS os recursos AWS desta camada.
# Recursos ainda recebem "Service" individualmente.
# ------------------------------------------------------------------
locals {
  finops_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
    Owner       = "solidarytech-fiap"
    Repository  = "solidarytech-fiap/solidarytech-app"
    Layer       = "security"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.finops_tags
  }
}
