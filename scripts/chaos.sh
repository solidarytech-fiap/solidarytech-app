#!/usr/bin/env bash
# Injeta falhas no donation-service (demo de SLO, alertas e self-healing).
#   BASE_URL=http://<elb> CHAOS_TOKEN=xxx ./scripts/chaos.sh on 0.3 0     # 30% de 5xx
#   BASE_URL=http://<elb> CHAOS_TOKEN=xxx ./scripts/chaos.sh on 0 800     # +800ms de latencia
#   BASE_URL=http://<elb> CHAOS_TOKEN=xxx ./scripts/chaos.sh off
# Obs: com varias replicas, cada POST atinge 1 pod. O script repete o POST
# para cobrir as replicas. Um 'rollout restart' (self-healing) zera tudo.
set -euo pipefail
BASE_URL="${BASE_URL:?defina BASE_URL}"
CHAOS_TOKEN="${CHAOS_TOKEN:?defina CHAOS_TOKEN (SSM /solidarytech/prod/donation/chaos-token)}"
mode="${1:-on}"
if [[ "$mode" == "off" ]]; then body='{"error_rate":0,"latency_ms":0}'; else body="{\"error_rate\":${2:-0.3},\"latency_ms\":${3:-0}}"; fi
for _ in $(seq 10); do
  curl -s -H "X-Chaos-Token: $CHAOS_TOKEN" -H 'Content-Type: application/json' -d "$body" "$BASE_URL/donation/admin/chaos"; echo
done
