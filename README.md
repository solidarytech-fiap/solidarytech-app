# SolidaryTech — App

Repositório de código e infraestrutura da plataforma SolidaryTech (Hackathon Fase 5 — FIAP PosTech).

Contém:
- `src/` — microsserviços (ngo, donation, volunteer)
- `terraform/` — IaC AWS (EKS, RDS, DynamoDB, SQS, ECR, SSM+KMS)
- `.github/workflows/` — pipelines CI/CD + DevSecOps
- `docs/` — documentação técnica

Repositório GitOps (manifests + ArgoCD): [`solidarytech-deploy`](https://github.com/solidarytech-fiap/solidarytech-deploy).
