# SolidaryTech - App e Infraestrutura

Hackathon Fase 5 (FIAP PosTech DevOps). Plataforma que conecta ONGs, doadores e voluntários, com SRE, FinOps, DevSecOps, ITSM/AIOps e Disaster Recovery.

Repositório GitOps (manifests, ArgoCD, observabilidade, Datadog): [`solidarytech-deploy`](https://github.com/solidarytech-fiap/solidarytech-deploy)

## Serviços

| Serviço | Stack | Dados | Porta | Rota pública |
|---|---|---|---|---|
| `ngo-service` | Python 3.12 / Flask / gunicorn | RDS PostgreSQL `ngo_db` | 8081 | `/ngo/*` |
| `donation-service` (caminho crítico) | Go 1.26 | RDS PostgreSQL `donation_db` + SQS | 8082 | `/donation/*` |
| `volunteer-service` | Python 3.12 / Flask / gunicorn | DynamoDB (GSI `ngo_id-index`) | 8083 | `/volunteer/*` |

Todos expõem `/health` (liveness), `/ready` (readiness, checa a dependência), `/metrics` (Golden Metrics) e traces OTLP. Os logs saem em JSON com `trace_id`, e há graceful shutdown. O donation-service tem também `/admin/chaos` (injeção de falhas protegida por token) para as demos de SLO e self-healing.

## Estrutura

```
src/                     microsserviços (+ Dockerfile, testes)
terraform/
  bootstrap/             bucket do state (1x)
  modules/               vpc, eks, rds, dynamodb, sqs, ecr, s3-backup
  environments/prod/     networking, security, data, platform, compute, finops
.github/workflows/       CI por serviço, reusable-{go,python,docker,gitops,terraform}, terraform-{ci,apply,destroy}, preflight
scripts/                 smoke/load/chaos, check-tags, rightsizing-report, dr-restore-db
docs/                    arquitetura, sre, finops, pcn, itsm, runbooks, DEPLOY, roteiro do vídeo, relatório
docker-compose.yaml      ambiente local (Postgres + LocalStack)
```

## Começo rápido

- Local: `docker compose up -d --build && ./scripts/local/smoke-test.sh`
- AWS: siga [`docs/DEPLOY.md`](docs/DEPLOY.md)

## Documentação

| Tema | Documento |
|---|---|
| Arquitetura e decisões | [docs/arquitetura.md](docs/arquitetura.md) |
| SRE: SLI, SLO, SLA, error budget, MTTR | [docs/sre.md](docs/sre.md) |
| FinOps: tags, rightsizing, forecast | [docs/finops.md](docs/finops.md) |
| PCN: RTO, RPO, DR | [docs/pcn.md](docs/pcn.md) |
| ITSM/AIOps: ciclo de incidentes | [docs/itsm.md](docs/itsm.md) |
| Runbooks | [docs/runbooks](docs/runbooks) |
| Passo a passo de deploy | [docs/DEPLOY.md](docs/DEPLOY.md) |
| Roteiro do vídeo / relatório | [docs/roteiro-video.md](docs/roteiro-video.md), [docs/relatorio.md](docs/relatorio.md) |
