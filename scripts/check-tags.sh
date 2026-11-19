#!/usr/bin/env bash
# Relatorio de conformidade de tags FinOps (evidencia para o relatorio).
# Lista os recursos com Project=SolidaryTech nas duas regioes e verifica as
# tags obrigatorias. Saida em Markdown.
set -euo pipefail
REQUIRED=(Project Environment CostCenter)

echo "## Conformidade de tags FinOps"
echo
echo "| Regiao | Recurso | Service | Environment | CostCenter |"
echo "|---|---|---|---|---|"
total=0; bad=0
for region in us-east-1 us-west-2; do
  json=$(aws resourcegroupstaggingapi get-resources --region "$region" \
    --tag-filters Key=Project,Values=SolidaryTech --output json)
  while IFS=$'\t' read -r arn svc env cc; do
    [[ -z "$arn" ]] && continue
    total=$((total+1))
    short=${arn#arn:aws:}
    echo "| $region | \`${short:0:80}\` | ${svc:--} | ${env:--} | ${cc:--} |"
    [[ "$env" != "Production" || "$cc" != "NGO-Core" ]] && bad=$((bad+1))
  done < <(echo "$json" | jq -r '.ResourceTagMappingList[] |
      (.Tags | from_entries) as $t |
      [.ResourceARN, ($t.Service // ""), ($t.Environment // ""), ($t.CostCenter // "")] | @tsv' \
      2>/dev/null || true)
done
echo
echo "**Total:** $total recursos | **Fora da politica (${REQUIRED[*]}):** $bad"
