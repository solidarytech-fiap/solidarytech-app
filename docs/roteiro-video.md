# Roteiro do vídeo (até 20 min)

Antes de gravar: ambiente de pé, tráfego rodando há 30 min ou mais (`load-test.sh`), abas abertas (GitHub Actions, ArgoCD, Grafana, Datadog, JSM, Slack) e terminal com kubeconfig.

## Parte 1 - Pitch executivo (~9 min)

| Tempo | Tema | Conteúdo | Tela |
|---|---|---|---|
| 0:00 | Problema | Exposição na TV, picos imprevisíveis, doação perdida é confiança perdida | slide |
| 1:00 | Solução | 3 microsserviços em EKS, tudo como código, GitOps | `arquitetura.md` (diagrama) |
| 2:30 | Confiabilidade | SLO 99,9% / 95% < 300 ms, SLA 99,5% com as ONGs, política de error budget | `sre.md` |
| 4:00 | Continuidade (PCN) | RPO 5 min / 15 min, RTO 30 min / 4 h, backups em outra região | `pcn.md` |
| 5:30 | Custos | Forecast de ~US$ 266/mês, tags por centro de custo, rightsizing de -82% de CPU requisitada, Spot = -US$ 59/mês | `finops.md` |
| 7:00 | Incidentes | Detecção preditiva (Watchdog), ciclo JSM/Slack, self-healing, MTTR | `itsm.md` (fluxo) |
| 8:30 | Fechamento | O que isso significa para a diretoria | slide |

## Parte 2 - Demo técnica (~10 min)

| Tempo | Demo | Evidência |
|---|---|---|
| 9:00 | **Terraform:** workflow *Terraform Apply* (camadas), `plan` com `tags_all`, resumo do relatório de tags, Tag Editor | tags FinOps |
| 10:30 | **CI/CD + DevSecOps:** push em `src/donation-service`; jobs test, lint, gosec, govulncheck, Trivy; push ECR; commit no deploy | pipeline verde |
| 12:00 | **GitOps:** ArgoCD sincronizando a nova tag (rolling update) e árvore do App-of-Apps | deploy via ArgoCD |
| 13:00 | **Rightsizing:** diff do overlay e dashboard FinOps (request vs uso) | limits/requests |
| 13:45 | **APM:** Datadog Service Map, um trace de `POST /donations` (spans `postgresql` e `sqs`) e o log correlacionado | distributed tracing |
| 15:00 | **SLO:** dashboard Grafana SLO, `chaos.sh on 0.3`, burn rate subindo, budget caindo, alertas disparando | Golden Metrics + SLO |
| 16:30 | **ITSM:** incidente no JSM, mensagem no Slack, workflow self-healing (resumo com horários), recuperação | MTTR |
| 18:00 | **DR:** workflow *DR Drill*: backup no S3 us-west-2, namespace apagado, restore, RTO medido; `velero backup get`; objetos no bucket | Backup/DR em ação |
| 19:30 | Encerramento | links e relatório | |
