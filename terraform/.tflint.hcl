plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Politica FinOps: falha o lint se algum recurso taggeavel nao tiver as tags
# obrigatorias (considera o default_tags do provider).
rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Project", "Environment", "CostCenter"]
}

# common-variables.tf e compartilhado entre camadas; nem toda camada usa todas.
rule "terraform_unused_declarations" {
  enabled = false
}

# tflint analisa os modulos isoladamente e nao enxerga o default_tags do
# provider que fica na camada (environments/prod/<layer>/versions.tf). Essa
# regra ja e aplicada na camada que invoca o modulo, entao desligamos aqui
# pra evitar notice ruidoso (falso positivo conhecido do plugin aws).
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible"
}
