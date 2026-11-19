# FinOps: orcamento mensal com alertas de 50/80/100% (real) e 100% (forecast),
# filtrado pela tag Project=SolidaryTech.
#
# AWS Academy: a API de Budgets pode ser negada pela politica do Learner Lab.
# Por isso esta camada e independente e o workflow a executa com
# continue-on-error. Em conta AWS normal funciona sem alteracao.
# Pre-requisito em conta normal: ativar a tag "Project" em
# Billing > Cost allocation tags.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$SolidaryTech"]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_emails
  }

  tags = { Service = "finops" }
}

variable "monthly_budget_usd" {
  description = "Orcamento mensal (ver docs/finops.md - forecast)"
  type        = string
  default     = "300"
}

variable "budget_emails" {
  description = "E-mails que recebem alertas (workflow: TF_VAR_budget_emails='[\"a@b.com\"]')"
  type        = list(string)
  validation {
    condition     = length(var.budget_emails) > 0
    error_message = "Informe ao menos um e-mail em budget_emails."
  }
}

output "budget_name" {
  value = aws_budgets_budget.monthly.name
}
