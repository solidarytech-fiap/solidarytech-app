#!/usr/bin/env bash
# Gera trafego continuo no donation-service para popular dashboards/SLO.
# Uso: BASE_URL=http://<elb-ingress> DURATION=300 RPS=10 ./scripts/load-test.sh
set -euo pipefail
BASE_URL="${BASE_URL:?defina BASE_URL}"
DURATION="${DURATION:-300}"
RPS="${RPS:-10}"
end=$((SECONDS + DURATION))
echo "Gerando ~${RPS} req/s por ${DURATION}s em $BASE_URL ..."
while (( SECONDS < end )); do
  for _ in $(seq "$RPS"); do
    curl -s -o /dev/null -H 'Content-Type: application/json' \
      -d "{\"ngo_id\":1,\"amount\":$((RANDOM % 500 + 1)),\"donor_name\":\"load\"}" "$BASE_URL/donation/donations" &
    curl -s -o /dev/null "$BASE_URL/ngo/ngos" &
    curl -s -o /dev/null "$BASE_URL/volunteer/volunteers/1" &
  done
  wait
  sleep 1
done
echo "Fim."
