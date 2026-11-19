# Config especifica dos modulos: NAO aplica a regra de tags porque o provider
# default_tags fica na camada (environments/prod/*/versions.tf) e o tflint nao
# atravessa modulo <-> caller (false positive do plugin aws).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
rule "aws_resource_missing_tags" { enabled = false }
rule "terraform_unused_declarations" { enabled = false }
