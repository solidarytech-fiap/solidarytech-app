# Plano de Continuidade de Negócios (PCN) - SolidaryTech

**Versão:** 1.0 · **Dono:** Engenharia de Plataforma · **Revisão:** trimestral, ou após cada incidente SEV1 ou drill

## 1. Resumo executivo

A SolidaryTech existe para que a doação chegue à ONG. Este plano garante que, diante da falha de um componente, de um cluster ou de uma região inteira da AWS, **as doações confirmadas não se percam** e o recebimento de novas doações volte em prazo definido.

| Compromisso | Valor |
|---|---|
| Perda máxima de doações confirmadas, falha dentro da região (RPO) | **5 minutos** |
| Perda máxima de doações confirmadas, perda da região (RPO) | **15 minutos** |
| Tempo máximo para voltar a receber doações, falha de cluster (RTO) | **30 minutos** |
| Tempo máximo para voltar a receber doações, perda da região (RTO) | **4 horas** |

## 2. Análise de impacto no negócio (BIA)

| Processo | Serviço | Criticidade | Impacto da parada | RTO | RPO |
|---|---|---|---|---|---|
| Receber doações | donation-service + donation_db + SQS | **Crítica** | perda direta de arrecadação e de confiança (exposição em TV) | 30 min (cluster) / 4 h (região) | 5 min / 15 min |
| Cadastro e consulta de ONGs | ngo-service + ngo_db | Alta | novas ONGs não entram; doações seguem | 4 h | 1 h |
| Voluntariado | volunteer-service + DynamoDB | Média | inscrições adiadas | 8 h | 5 min (PITR na região) |
| Observabilidade | Prometheus/Grafana/Loki | Média | perda de visibilidade, não de negócio | 4 h | não aplicável |

## 3. Estratégia de proteção por camada

| Camada | Mecanismo | RPO | Onde está |
|---|---|---|---|
| Código e manifests | Git (GitHub): fonte da verdade do GitOps | 0 | `solidarytech-app`, `solidarytech-deploy` |
| Infraestrutura | Terraform modular e state versionado em S3 | 0 | `terraform/` |
| Estado do cluster | **Velero**: backup a cada hora (namespace solidarytech) e diário (cluster) para S3 em **us-west-2** | 1 h | `k8s/apps/30-velero.yaml`, `k8s/dr/velero` |
| Doações (PostgreSQL) | RDS automated backups com PITR | 5 min | camada `data` |
| Doações (cross-region) | CronJob `pg_dump` a cada **15 min** para S3 us-west-2 (versionado) | 15 min | `k8s/base/dr/pg-dump-cronjob.yaml` |
| ONGs (PostgreSQL) | PITR e `pg_dump` de hora em hora para us-west-2 | 5 min / 1 h | idem |
| Voluntários (DynamoDB) | Point-in-Time Recovery (35 dias) | ~5 min | módulo `dynamodb` |
| Imagens de container | ECR com replicação para us-west-2 | 0 | camada `platform` |
| Eventos de doação | SQS com DLQ de 14 dias | 0 | módulo `sqs` |

Opção do enunciado implementada: **Opção A (Velero com backup cross-region para bucket externo)**. Ela é complementada por backups lógicos do banco e por IaC modular, que permite subir o ambiente em outra região (ver o runbook de failover).

## 4. Cenários e resposta

| # | Cenário | Detecção | Resposta | RTO esperado |
|---|---|---|---|---|
| C1 | Pod ou node falha | probes, HPA, alerta `DonationNoReplicasAvailable` | automática: Kubernetes recria; PDB e spread entre nodes | < 1 min |
| C2 | Deploy defeituoso | burn rate do SLO, Watchdog | `git revert` da tag no `solidarytech-deploy`, ArgoCD reverte | < 10 min |
| C3 | Serviço degradado (memória, conexões) | monitor 5xx do Datadog | self-healing (`rollout restart`) automático | < 5 min |
| C4 | Corrupção ou exclusão de dados de doação | consulta, auditoria | RDS PITR para um instante antes do erro | < 1 h |
| C5 | **Perda do cluster EKS** (namespace apagado, cluster destruído) | `ServiceDown`, ArgoCD | `Terraform Apply` (compute) + ArgoCD + `velero restore` | **< 30 min** (medido no drill) |
| C6 | **Perda da região us-east-1** | AWS Health, todos os alertas | Terraform em us-west-2 + restore do último `pg_dump` (runbook `dr-regional-failover.md`) | **< 4 h** |

## 5. Ativação do plano

1. **Declaração:** o Incident Commander (on-call primário) declara o desastre quando um cenário C4-C6 é confirmado, ou quando o RTO de C1-C3 estoura.
2. **Comunicação:** status para as ONGs parceiras em até 30 min (template em `itsm.md`) e para a diretoria por e-mail e telefone.
3. **Execução:** seguir o runbook do cenário. Toda ação é registrada na linha do tempo do incidente no JSM.
4. **Validação:** `scripts/local/smoke-test.sh` contra o ambiente recuperado, mais o dashboard SLO.
5. **Retorno:** voltar à região primária em janela planejada (failback), com novo backup antes.
6. **Encerramento:** post-mortem em até 5 dias úteis.

## 6. Testes do plano

| Teste | Frequência | Como | Critério de sucesso |
|---|---|---|---|
| Drill de cluster (C5) | mensal e antes da entrega | workflow `DR Drill` no `solidarytech-deploy`: backup, `delete namespace`, restore | serviços saudáveis e RTO medido < 30 min |
| Restore de banco | mensal | `scripts/dr-restore-db.sh` em banco temporário | contagem de doações confere |
| Failover regional (C6) | semestral | runbook `dr-regional-failover.md` | doação aceita em us-west-2 |

Resultado do último drill: *preencher com o resumo do workflow (RTO medido, horário do backup usado)*.

## 7. Riscos residuais e roadmap

| Risco | Mitigação futura |
|---|---|
| RDS single-AZ: a falha de AZ exige restore | Multi-AZ no `donation_db` (+US$ 13/mês) |
| DynamoDB sem cópia em outra região | DynamoDB Global Tables ou export periódico para S3 |
| Prometheus sem volume persistente | histórico de SLO persistido no Datadog; em produção, PVC gp3 |
| Failover regional manual (4 h) | Warm standby em us-west-2 (Opção B) com RTO < 1 h |
