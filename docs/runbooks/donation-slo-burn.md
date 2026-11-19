# Runbook - donation-service queimando error budget

**Alertas:** `DonationSLOAvailabilityBurnRate*`, `DonationSLOLatencyBurnRate*` (Prometheus), `[SolidaryTech] donation-service - SLO disponibilidade: burn rate alto` (Datadog). **Severidade:** SEV1 (14,4x / 6x) ou SEV2 (3x / 1x).

## 1. Confirmar impacto (2 min)
- Grafana: **SolidaryTech - SLO e Error Budget**. Ver qual SLI está queimando e o budget restante.
- Grafana: **Golden Signals**, filtrando `donation-service`. Erros, latência p95 e réplicas.
- Ver se houve deploy recente: histórico da Application `solidarytech` no ArgoCD (*History and rollback*).

## 2. Mitigar primeiro
| Sintoma | Ação |
|---|---|
| Começou logo após um deploy | `git revert` do commit `deploy(donation-service): <sha>` no `solidarytech-deploy`. O ArgoCD aplica em ~1 min. |
| 5xx sem deploy recente | Self-healing já rodou? Ver o workflow *Self-Healing* no `solidarytech-deploy`. Se não, rodar manualmente com `service=donation-service`. |
| Latência alta e CPU no limite | HPA no máximo? `kubectl -n solidarytech get hpa`. Subir `maxReplicas` via commit. |
| Erros de conexão com o banco nos logs | RDS: CPU, conexões e eventos (`aws rds describe-events --source-identifier solidarytech-donation`) |
| Chaos ativo (demo) | `./scripts/chaos.sh off` ou rollout restart |

## 3. Diagnosticar
- Datadog APM > `donation-service` > Traces com `status:error`. Ver qual span falhou (`postgresql`, `sqs.SendMessage`).
- Loki: `{namespace="solidarytech", app="donation-service"} |= "error" | json`
- Correlação: copie o `trace_id` do log e busque no APM.

## 4. Encerrar
- Monitor recuperado. Resolver o incidente no JSM com o MTTR.
- SEV1/SEV2: abrir o post-mortem (`docs/postmortem-template.md`).
