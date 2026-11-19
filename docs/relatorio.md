# Relatório de Entrega - Hackathon Fase 5 - SolidaryTech

> Base para o PDF: `pandoc docs/relatorio.md -o relatorio.pdf` (ou exportar pelo editor). Substitua os campos `<...>` e insira os prints indicados em **[EVIDÊNCIA]**.

## 1. Identificação

| Nome | RM | Usuário GitHub |
|---|---|---|
| Alexander Auerhahn | <RM> | auerhahn1 |
| <colega> | <RM> | <usuário> |

## 2. Links

- Repositório de aplicação e IaC: https://github.com/solidarytech-fiap/solidarytech-app
- Repositório GitOps: https://github.com/solidarytech-fiap/solidarytech-deploy
- Vídeo: <link>

## 3. Arquitetura e fundação DevOps (Fases 1 a 4)

Resumo de `docs/arquitetura.md` (diagramas).

- **[EVIDÊNCIA]** Dockerfiles multi-stage e tamanho das imagens (resumo do job do CI)
- **[EVIDÊNCIA]** Terraform Apply verde com as 6 camadas
- **[EVIDÊNCIA]** Pipeline DevSecOps: jobs test, lint, SAST, SCA, Trivy image
- **[EVIDÊNCIA]** ArgoCD: árvore do App-of-Apps, todas as Applications `Synced/Healthy`
- **[EVIDÊNCIA]** Grafana Golden Signals, Loki e trace no Datadog APM

## 4. SRE

Definição formal de SLI, SLO e SLA: copiar a seção 2 de `docs/sre.md`.

- **[EVIDÊNCIA]** Dashboard "SLO e Error Budget" (Grafana) antes e durante o incidente simulado
- **[EVIDÊNCIA]** Alertas multi-burn-rate firing (Prometheus/Alertmanager) e SLO no Datadog
- **[EVIDÊNCIA]** MTTR: linha do tempo do self-healing (resumo do workflow) e do incidente no JSM

## 5. FinOps

Copiar as seções 1, 3 e 4 de `docs/finops.md`.

- **[EVIDÊNCIA]** `tags_all` no plan e relatório `check-tags.sh` (0 recursos fora da política)
- **[EVIDÊNCIA]** Tag Editor filtrando `Project=SolidaryTech`
- **[EVIDÊNCIA]** Rightsizing: diff do commit e dashboard FinOps antes e depois
- **[EVIDÊNCIA]** Budget (ou plan da camada finops)

## 6. Segurança e Disaster Recovery

PCN: copiar `docs/pcn.md` (BIA, RTO/RPO, cenários, ativação). Estratégia de DR: Opção A (Velero cross-region) mais `pg_dump` a cada 15 min para us-west-2 e replicação do ECR.

- **[EVIDÊNCIA]** `velero backup get`, objetos em `s3://solidarytech-dr-backups-<conta>/velero` e `/postgres` (us-west-2)
- **[EVIDÊNCIA]** Resumo do workflow DR Drill com o RTO medido
- **[EVIDÊNCIA]** Controles de segurança: Trivy, Checkov, External Secrets (nenhum segredo no Git), Pod Security

## 7. ITSM / AIOps

Copiar o diagrama e as tabelas de `docs/itsm.md`.

- **[EVIDÊNCIA]** Watchdog story / monitor AIOps
- **[EVIDÊNCIA]** Incidente no JSM e notificação no Slack
- **[EVIDÊNCIA]** Post-mortem do incidente simulado (`postmortem-template.md` preenchido)

## 8. Desafios e decisões

| Desafio | Decisão |
|---|---|
| AWS Academy sem criação de IAM Roles (sem IRSA) | LabRole no node via IMDSv2 (hop limit 2); nenhuma chave estática em pod |
| Secrets Manager bloqueado | SSM Parameter Store + External Secrets |
| Código fornecido não compilava (`go.mod` inválido, imports não usados) | Corrigido; pgx v4 (EOL, CVE sem fix) migrado para v5 |
| Trial do Datadog de 14 dias | Stack OSS (Prometheus/Grafana/Loki/OTel) nas semanas 1-6; Datadog ativado por GitOps na semana 7 |
| Créditos limitados | Sem NAT, destroy entre sessões, rightsizing, forecast e budget |
