#!/usr/bin/env bash
# Smoke test end-to-end. Uso:
#   ./scripts/local/smoke-test.sh                       (local, portas 8081-8083)
#   BASE_URL=http://<elb-ingress> ./scripts/local/smoke-test.sh   (cluster, via Ingress)
set -euo pipefail

if [[ -n "${BASE_URL:-}" ]]; then
  NGO="$BASE_URL/ngo"; DON="$BASE_URL/donation"; VOL="$BASE_URL/volunteer"
else
  NGO="http://localhost:8081"; DON="http://localhost:8082"; VOL="http://localhost:8083"
fi

check() { local name=$1 expected=$2 code=$3; if [[ "$code" == "$expected" ]]; then echo "OK   $name ($code)"; else echo "FAIL $name (esperado $expected, obtido $code)"; FAILED=1; fi; }
FAILED=0
EMAIL="smoke-$(date +%s)@solidary.org"

check "ngo /health"        200 "$(curl -s -o /dev/null -w '%{http_code}' "$NGO/health")"
check "donation /health"   200 "$(curl -s -o /dev/null -w '%{http_code}' "$DON/health")"
check "volunteer /health"  200 "$(curl -s -o /dev/null -w '%{http_code}' "$VOL/health")"
check "POST /ngos"         201 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "{\"name\":\"Smoke\",\"email\":\"$EMAIL\",\"cause\":\"Teste\",\"city\":\"SP\"}" "$NGO/ngos")"
check "POST /donations"    201 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{"ngo_id":1,"amount":25.5,"donor_name":"Smoke"}' "$DON/donations")"
check "POST /volunteers"   201 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{"name":"Smoke","email":"v@s.org","ngo_id":1}' "$VOL/volunteers")"
check "GET /volunteers/1"  200 "$(curl -s -o /dev/null -w '%{http_code}' "$VOL/volunteers/1")"
check "GET /donations"     200 "$(curl -s -o /dev/null -w '%{http_code}' "$DON/donations")"

exit $FAILED
