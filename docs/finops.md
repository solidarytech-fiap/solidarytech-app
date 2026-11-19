# FinOps - SolidaryTech

Orçamento de ONG: cada recurso precisa estar identificado, justificado e dimensionado pelo uso real.

## 1. Estratégia de tagging (Terraform)

Todas as camadas declaram `default_tags` no provider AWS (`terraform/environments/prod/*/versions.tf`). Com isso, **todo recurso** recebe as tags abaixo sem depender de quem escreve o módulo:

| Tag | Valor | Uso |
|---|---|---|
| `Project` | `SolidaryTech` | filtro do Budget e do Cost Explorer |
| `Environment` | `Production` | separação por ambiente |
| `CostCenter` | `NGO-Core` | rateio contábil |
| `ManagedBy` | `Terraform` | detecta recurso criado fora do IaC |
| `Owner` | `solidarytech-fiap` | responsável |
| `Repository` | `solidarytech-fiap/solidarytech-app` | rastreabilidade |
| `Layer` | networking, data, compute... | custo por camada |
| `Service` | ngo-service, donation-service, platform-eks... | custo por microsserviço (por recurso) |

Pontos que costumam escapar e foram tratados:
- **Instâncias EC2 e volumes EBS dos nodes:** o Auto Scaling do node group não herda `default_tags`. O launch template (`modules/eks`) propaga as tags via `tag_specifications` (instance, volume, network-interface).
- **Bucket na região de DR:** provider `aws.dr` com as mesmas tags e mais `DRRole=secondary`.

Mecanismos que garantem a política:
- `tflint` com a regra `aws_resource_missing_tags` (Project, Environment, CostCenter) no workflow *Terraform CI*. O PR falha se faltar tag.
- `scripts/check-tags.sh` gera o relatório de conformidade (recursos por região e tags). Ele roda ao final do *Terraform Apply* e o resultado fica no resumo do job (evidência).
- Kubernetes: labels `cost-center: ngo-core` e `app.kubernetes.io/part-of: solidarytech` em todos os objetos do namespace (Kustomize). O dashboard FinOps usa esses labels para alocar custo por namespace.

> Em conta AWS normal, ative `Project`, `CostCenter` e `Service` em *Billing > Cost allocation tags* para usá-las no Cost Explorer e no Budget. No AWS Academy, o Billing não é acessível.

## 2. Rightsizing (via GitOps)

### Método

1. A base (`k8s/base/services/*/deployment.yaml`) começou com valores conservadores, sem dados de uso: Go 200m/256Mi e Python 250m/512Mi de request.
2. Com tráfego real e de carga (`scripts/load-test.sh`), coletamos 7 dias de métricas (cAdvisor/kube-state-metrics no Prometheus).
3. `scripts/rightsizing-report.sh` calcula, por container:
   - request de CPU = p95 do uso × 1,3
   - request de memória = p95 × 1,3
   - limit de memória = máximo × 1,5
4. Os novos valores entram por **commit** no overlay `k8s/overlays/prod/kustomization.yaml` (patches de `resources`). O ArgoCD aplica. O histórico do Git é a trilha de auditoria.
5. O dashboard Grafana **SolidaryTech - FinOps (Rightsizing)** mostra request vs uso, ociosidade e custo alocado por namespace. Prints de antes e depois vão para o relatório.

### Resultado (preencher com a saída do `rightsizing-report.sh`)

| Container | Request CPU antes | Request CPU depois | Request mem antes | Request mem depois | Limit mem depois |
|---|---|---|---|---|---|
| donation-service | 200m | 50m | 256Mi | 48Mi | 128Mi |
| ngo-service | 250m | 30m | 512Mi | 128Mi | 256Mi |
| volunteer-service | 250m | 30m | 512Mi | 128Mi | 256Mi |

Efeito: os requests de CPU dos 3 serviços (com o mínimo do HPA: donation 2 réplicas, demais 1) caem de 0,9 vCPU para 0,16 vCPU, e os de memória de 1,5 GiB para 352 MiB. Essa folga comporta os picos (HPA até 6 réplicas no donation) sem um 4º node.

> Os valores "depois" do overlay são uma estimativa inicial do perfil dos runtimes (Go ~20-30 MiB; Python + OTel ~90-110 MiB). Depois de 7 dias de métricas, substitua pelos valores do relatório e registre a tabela real aqui.

## 3. Forecast mensal (us-east-1, on-demand, 730 h/mês)

Preços públicos da AWS em us-east-1 (referência: [AWS Pricing Calculator](https://calculator.aws/)). Confirme no Calculator antes da entrega, porque podem variar.

| Item | Cálculo | US$/mês |
|---|---|---|
| EKS control plane | 0,10 × 730 | 73,00 |
| EC2 nodes 3× t3.medium | 0,0416 × 730 × 3 | 91,10 |
| EBS gp3 dos nodes 3× 20 GB | 0,08 × 60 | 4,80 |
| RDS 2× db.t3.micro (single-AZ) | 0,018 × 730 × 2 | 26,28 |
| RDS storage gp3 2× 20 GB | 0,115 × 40 | 4,60 |
| Load Balancers (ingress-nginx + argocd-server) | 0,025 × 730 × 2 | 36,50 |
| IPv4 públicos (3 nodes + ~4 dos LBs) | 0,005 × 730 × 7 | 25,55 |
| DynamoDB on-demand (~1M leituras/escritas) | estimativa | 1,00 |
| SQS (até 1M req/mês grátis) | free tier | 0,00 |
| ECR (~2 GB + réplica us-west-2) | 0,10 × 4 | 0,40 |
| S3 DR us-west-2 (dumps a cada 15 min + Velero, ~3 GB) | storage + PUTs | 0,30 |
| CloudWatch Logs (audit do EKS, ~5 GB) | 0,50 × 5 | 2,50 |
| Transferência entre regiões (backups) | ~2 GB × 0,02 | 0,04 |
| **Total base** | | **≈ 266** |
| Pico de acesso (TV): +1 node por ~5 dias/mês | 0,0416 × 24 × 5 | +5,00 |
| **Forecast com picos** | | **≈ 271** |
| NAT Gateway (evitado por decisão de arquitetura) | 0,045 × 730 + dados | (economia de 32,85+) |
| Datadog após o trial (APM, 3 hosts) | referência de lista | ~93 (fora do forecast AWS) |

**Budget:** US$ 300/mês na camada `finops`, com alertas em 50%, 80% e 100% (real) e 100% (forecast). Filtro `Project=SolidaryTech`.

### Projeção trimestral

| Mês | Cenário | US$ |
|---|---|---|
| 1 | baseline + rightsizing | 266 |
| 2 | crescimento de 30% no tráfego (HPA absorve, sem novo node) | 271 |
| 3 | com as otimizações da seção 4 (Spot + Graviton + 1 LB) | ~178 |

## 4. Recomendações de otimização nativas de nuvem

| # | Recomendação | Economia estimada | Esforço |
|---|---|---|---|
| 1 | **Spot no node group** (`capacity_type = "SPOT"` no `compute`, com 2-3 tipos de instância). Workloads stateless com PDB e `maxUnavailable: 0` toleram interrupções. | EC2: 91 -> ~32 (**-US$ 59/mês, -65%**) | 1 variável |
| 2 | **Graviton:** `t4g.medium` nos nodes e `db.t4g.micro` no RDS (imagens multi-arch no CI) | -20% EC2 e -11% RDS (~US$ 21/mês) | médio (build arm64) |
| 3 | **Um único Load Balancer:** expor o ArgoCD pelo próprio ingress-nginx (host/path) em vez de um LB próprio | -US$ 18,25 LB e -US$ 7,30 IPv4 | baixo |
| 4 | **Compute Savings Plan** de 1 ano (sem adiantamento) para a capacidade base dos nodes | ~-27% sobre o on-demand restante | baixo (decisão financeira) |
| 5 | Desligar fora do horário (dev/staging) ou `terraform destroy` entre sessões, como fazemos no Academy | até -70% em não-produção | já aplicado |
| 6 | Já aplicado: DynamoDB on-demand, lifecycle ECR (10 imagens), S3 IA após 30 dias e expiração em 90, SQS long polling, gateway endpoints S3/DynamoDB gratuitos, sem NAT | - | - |

**Recomendação prioritária:** a nº 1 (Spot). É uma linha de Terraform e corta ~22% do custo total.

## 5. Evidências para o relatório

- [ ] Print do `terraform plan` mostrando `tags_all` com as tags obrigatórias
- [ ] Resumo do job *Relatório de tags FinOps* (`check-tags.sh`) com 0 recursos fora da política
- [ ] AWS Tag Editor / Resource Groups filtrando `Project=SolidaryTech` nas duas regiões
- [ ] Dashboard FinOps (Grafana) antes e depois do rightsizing
- [ ] Diff do commit de rightsizing no `solidarytech-deploy`
- [ ] Budget criado (se o Academy permitir) ou `terraform plan` da camada finops
