# Segredos gerados pelo Terraform e guardados no SSM Parameter Store
# (SecureString, chave aws/ssm). O External Secrets Operator sincroniza para
# Secrets do Kubernetes -> nenhum segredo no Git.
# (Secrets Manager e bloqueado no AWS Academy.)

locals {
  databases = {
    ngo      = { service = "ngo-service" }
    donation = { service = "donation-service" }
  }
}

resource "random_password" "db" {
  for_each = local.databases
  length   = 24
  special  = false
}

resource "aws_ssm_parameter" "db_credentials" {
  for_each = local.databases

  name        = "/${var.name}/prod/${each.key}/db-credentials"
  description = "Usuario/senha do PostgreSQL do ${each.value.service}"
  type        = "SecureString"
  value = jsonencode({
    username = "solidary_${each.key}"
    password = random_password.db[each.key].result
  })

  tags = { Service = each.value.service }
}

# Token que protege o endpoint /admin/chaos (demo de SLO/self-healing).
resource "random_password" "chaos_token" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "chaos_token" {
  name        = "/${var.name}/prod/donation/chaos-token"
  description = "Token do endpoint /admin/chaos do donation-service"
  type        = "SecureString"
  value       = random_password.chaos_token.result
  tags        = { Service = "donation-service" }
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "aws_ssm_parameter" "grafana_admin" {
  name        = "/${var.name}/prod/observability/grafana-admin"
  description = "Credenciais do admin do Grafana"
  type        = "SecureString"
  value = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
  tags = { Service = "observability" }
}

output "db_credentials_parameters" {
  value = { for k, v in aws_ssm_parameter.db_credentials : k => v.name }
}
