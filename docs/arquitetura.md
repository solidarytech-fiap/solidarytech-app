# Arquitetura - SolidaryTech

## Visão geral

```mermaid
graph TB
    U[Doadores / ONGs / Voluntários] --> LB[AWS Load Balancer]
    subgraph us-east-1 [us-east-1 - Região primária]
      subgraph VPC [VPC 10.20.0.0/16 - 2 AZs]
        LB --> ING[ingress-nginx]
        subgraph EKS [EKS solidarytech-eks - 3x t3.medium]
          ING --> NGO[ngo-service<br/>Python/Flask]
          ING --> DON[donation-service<br/>Go - caminho crítico]
          ING --> VOL[volunteer-service<br/>Python/Flask]
          OTEL[OTel Collector]
          PROM[Prometheus + Alertmanager]
          GRAF[Grafana]
          LOKI[Loki + Promtail]
          ESO[External Secrets]
          VEL[Velero]
          ARGO[ArgoCD]
        end
        RDS1[(RDS ngo_db)]
        RDS2[(RDS donation_db)]
      end
      SQS[SQS solidary-donations + DLQ]
      DDB[(DynamoDB SolidaryTechVolunteers)]
      SSM[SSM Parameter Store]
      ECR[ECR]
    end
    subgraph us-west-2 [us-west-2 - Região de DR]
      S3[(S3 dr-backups<br/>Velero + pg_dump)]
      ECR2[ECR réplica]
    end
    NGO --> RDS1
    DON --> RDS2
    DON --> SQS
    VOL --> DDB
    NGO & DON & VOL -- OTLP traces --> OTEL
    PROM -- scrape /metrics --> NGO & DON & VOL
    OTEL -- traces/metrics --> DD[Datadog APM + Watchdog]
    ESO --> SSM
    VEL -- backup cross-region --> S3
    DON -. CronJob pg_dump 15 min .-> S3
    ECR -- replicação --> ECR2
    DD --> JSM[Jira Service Management] --> SLACK[Slack #alerts]
    DD -- webhook --> GHA[GitHub Actions self-healing] --> EKS
```

## Fluxo de entrega (CI/CD + GitOps)

```mermaid
graph LR
    DEV[git push src/*] --> CI[GitHub Actions<br/>testes + lint]
    CI --> SEC[SAST gosec/bandit<br/>SCA govulncheck/pip-audit/Trivy fs]
    SEC --> IMG[docker build<br/>Trivy image - bloqueia CRITICAL]
    IMG --> ECR[ECR tag = SHA imutável]
    ECR --> GIT[commit da nova tag em<br/>solidarytech-deploy/overlays/prod]
    GIT --> ARGO[ArgoCD auto-sync]
    ARGO --> K8S[EKS rolling update<br/>maxUnavailable 0]
```

Não há `kubectl apply` manual nem recurso criado no console:

| Camada | Ferramenta | Onde |
|---|---|---|
| Infra AWS (rede, EKS, RDS, DynamoDB, SQS, ECR, S3, SSM, Budgets) | Terraform | `solidarytech-app/terraform` (workflow *Terraform Apply*) |
| Bootstrap do cluster (ArgoCD) | Helm via GitHub Actions | `solidarytech-deploy/.github/workflows/argocd-install.yml` |
| Tudo dentro do cluster | ArgoCD (App-of-Apps) | `solidarytech-deploy/k8s/apps` |
| Alertas, SLOs, webhook no Datadog | Terraform | `solidarytech-deploy/terraform/datadog` |

## Camadas Terraform

| Camada | Recursos | Depende de |
|---|---|---|
| `bootstrap` (1x, local) | bucket S3 do state (versionado, criptografado) | - |
| `networking` | VPC, 2 subnets públicas + 2 privadas, IGW, gateway endpoints S3/DynamoDB, SG default fechado | - |
| `security` | senhas aleatórias e tokens no SSM (SecureString) | - |
| `data` | 2x RDS PostgreSQL 16 (privado, TLS, PITR), DynamoDB on-demand + GSI + PITR, SQS + DLQ, parâmetros de conexão no SSM | networking, security |
| `platform` | 3 ECR (scan on push, imutável, lifecycle), replicação ECR -> us-west-2, bucket S3 de DR em us-west-2 | - |
| `compute` | EKS 1.36, node group gerenciado com launch template (IMDSv2, EBS gp3 criptografado, tags propagadas), add-ons gerenciados | networking |
| `finops` | AWS Budget mensal com alertas 50/80/100% e forecast | - |

## Decisões e restrições do AWS Academy

| Restrição | Decisão |
|---|---|
| Não é possível criar IAM Roles (sem IRSA/Pod Identity) | Cluster e nodes usam a `LabRole`. Pods usam a credencial do node via IMDSv2 com hop limit 2. Nenhuma access key fica em pod ou no Git. |
| Secrets Manager bloqueado | SSM Parameter Store (SecureString) + External Secrets Operator |
| Créditos limitados | Sem NAT Gateway (nodes em subnet pública com SG), DynamoDB on-demand, 1 réplica de RDS por banco, destroy entre sessões |
| Credenciais temporárias | Secrets do GitHub renovados por sessão; workflow *Preflight Check* valida antes de tudo |

## Segurança aplicada

- Imagens: multi-stage, distroless (Go) e slim (Python), usuário não-root, `readOnlyRootFilesystem`, `drop: ALL`, seccomp `RuntimeDefault`.
- Namespace com Pod Security Admission (`enforce: baseline`, `warn/audit: restricted`).
- RDS em subnets privadas, SG restrito à VPC, `rds.force_ssl=1`, storage criptografado.
- S3 de DR: versionamento, SSE, bloqueio de acesso público, política só-HTTPS.
- Pipeline: SAST (gosec, bandit), SCA (govulncheck, pip-audit, Trivy fs), scan de imagem (Trivy, bloqueia CRITICAL), IaC scan (Checkov, tflint), segredos (Trivy secret scanner).
- Endpoint `/admin/chaos` (injeção de falhas para demo) protegido por token do SSM.
