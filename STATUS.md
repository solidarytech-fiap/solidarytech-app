# Status do projeto

Atualize a cada sessão do AWS Academy (o ambiente é destruído entre sessões).

| Fase | Status | Evidência coletada |
|---|---|---|
| 0. Bootstrap (bucket de state, PAT, org secrets) | [ ] | |
| 1. Terraform Apply verde (6 camadas) | [ ] | |
| 2. CI dos 3 serviços verde, imagens no ECR | [ ] | |
| 3. ArgoCD: todas as Applications Synced/Healthy | [ ] | |
| 4. Smoke test via Ingress | [ ] | |
| 5. Dashboards Grafana com dados (Golden, SLO, FinOps) | [ ] | |
| 6. Velero: backups no S3 us-west-2 + DR Drill com RTO medido | [ ] | |
| 7. pg_dump a cada 15 min no S3 us-west-2 | [ ] | |
| 8. Rightsizing com dados reais (commit no overlay) | [ ] | |
| 9. Datadog: APM, Service Map, Watchdog, SLOs, monitores | [ ] | |
| 10. JSM + Slack + self-healing ponta a ponta | [ ] | |
| 11. Vídeo gravado | [ ] | |
| 12. Relatório PDF | [ ] | |

## Pendências conhecidas para validar no primeiro deploy
- Confirmar que o Learner Lab permite: EKS 1.36, launch template com IMDSv2, `aws_ecr_replication_configuration` (senão `enable_ecr_replication=false`) e Budgets (camada finops com `continue-on-error`).
- Confirmar o nome das métricas `trace.*` no Datadog (`trace_operation` em `terraform/datadog/variables.tf`).
- Build local com podman: falta `subuid/subgid` para o usuário (`sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER && podman system migrate`). O CI usa docker e não depende disso.
