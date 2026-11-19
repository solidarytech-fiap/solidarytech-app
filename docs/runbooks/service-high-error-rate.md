# Runbook - taxa de erros 5xx alta (qualquer serviço)

**Alertas:** `ServiceHighErrorRate` (Prometheus), `[SolidaryTech] <serviço> - erros 5xx` (Datadog).

1. O self-healing roda automaticamente (webhook do Datadog -> `self-healing.yml`). Veja o resumo do job: horário, rollout e health check.
2. Health check falhou após o restart: o problema não é transitório. Escale para o IC (SEV conforme `itsm.md`).
3. Verifique as dependências:
   - ngo/donation: RDS (`kubectl -n solidarytech logs deploy/<svc> | grep -i database`)
   - volunteer: DynamoDB (throttling e permissões da LabRole)
   - donation: SQS (`sqs_publish_total{result="failure"}`)
   - Secrets: `kubectl -n solidarytech get externalsecrets` (todos `SecretSynced`?)
4. Deploy recente: rollback via `git revert` no `solidarytech-deploy`.
5. Encerrar no JSM e, se for SEV1/SEV2, fazer o post-mortem.
