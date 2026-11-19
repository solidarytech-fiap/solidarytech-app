#!/usr/bin/env bash
# Relatorio de rightsizing: compara requests/limits atuais com o uso real
# (Prometheus) e sugere novos valores. Saida em Markdown (evidencia FinOps).
#
# Regra: request CPU/mem = p95 do uso na janela x 1.3 ; limit mem = max x 1.5
# Uso: WINDOW=7d ./scripts/rightsizing-report.sh   (requer kubeconfig do cluster)
set -euo pipefail
WINDOW="${WINDOW:-7d}"
NS="${NS:-solidarytech}"
PORT=19090

kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus "$PORT:9090" >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT
sleep 4

q() { curl -s --get "http://localhost:$PORT/api/v1/query" --data-urlencode "query=$1" \
      | jq -r '.data.result[] | "\(.metric.container) \(.value[1])"'; }

declare -A CPU_P95 MEM_P95 MEM_MAX CPU_REQ MEM_REQ MEM_LIM
while read -r c v; do CPU_P95[$c]=$v; done < <(q "max by (container) (quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace=\"$NS\",container=~\".*-service\"}[5m])[$WINDOW:5m]))")
while read -r c v; do MEM_P95[$c]=$v; done < <(q "max by (container) (quantile_over_time(0.95, container_memory_working_set_bytes{namespace=\"$NS\",container=~\".*-service\"}[$WINDOW]))")
while read -r c v; do MEM_MAX[$c]=$v; done < <(q "max by (container) (max_over_time(container_memory_working_set_bytes{namespace=\"$NS\",container=~\".*-service\"}[$WINDOW]))")
while read -r c v; do CPU_REQ[$c]=$v; done < <(q "max by (container) (kube_pod_container_resource_requests{namespace=\"$NS\",resource=\"cpu\",container=~\".*-service\"})")
while read -r c v; do MEM_REQ[$c]=$v; done < <(q "max by (container) (kube_pod_container_resource_requests{namespace=\"$NS\",resource=\"memory\",container=~\".*-service\"})")
while read -r c v; do MEM_LIM[$c]=$v; done < <(q "max by (container) (kube_pod_container_resource_limits{namespace=\"$NS\",resource=\"memory\",container=~\".*-service\"})")

echo "## Rightsizing - janela $WINDOW ($(date -u +%F))"
echo
echo "| Container | CPU p95 | CPU request atual | CPU request sugerido | Mem p95 | Mem max | Mem request atual | Mem request sugerido | Mem limit sugerido |"
echo "|---|---|---|---|---|---|---|---|---|"
for c in "${!CPU_P95[@]}"; do
  awk -v c="$c" -v cp="${CPU_P95[$c]:-0}" -v cr="${CPU_REQ[$c]:-0}" -v mp="${MEM_P95[$c]:-0}" -v mm="${MEM_MAX[$c]:-0}" \
      -v mr="${MEM_REQ[$c]:-0}" 'BEGIN {
    sc = cp * 1.3 * 1000; if (sc < 10) sc = 10
    sm = mp * 1.3 / 1048576; sl = mm * 1.5 / 1048576; if (sl < sm * 1.5) sl = sm * 1.5
    printf "| %s | %.0fm | %.0fm | **%.0fm** | %.0fMi | %.0fMi | %.0fMi | **%.0fMi** | **%.0fMi** |\n",
      c, cp*1000, cr*1000, sc, mp/1048576, mm/1048576, mr/1048576, sm, sl }'
done
echo
echo "Aplique os valores sugeridos em solidarytech-deploy/k8s/overlays/prod/kustomization.yaml (commit -> ArgoCD)."
