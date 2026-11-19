# Guia de deploy - do zero ao ambiente completo

Tempo total estimado: ~60 min (a maior parte é espera do EKS e do RDS).

## 0. Uma vez só (persiste entre sessões)

### 0.1 Token do gh com escopo para workflows e secrets da org
```bash
gh auth refresh -h github.com -s workflow,admin:org
```

### 0.2 Bucket do Terraform state
```bash
cd terraform/bootstrap
terraform init && terraform apply      # anote o output state_bucket
```
O state do bootstrap é local (`terraform.tfstate`, no .gitignore). Guarde-o e não apague.

### 0.3 PAT para GitOps (CI -> repo deploy)
GitHub > Settings > Developer settings > Fine-grained token:
- Resource owner: `solidarytech-fiap`. Repositório: `solidarytech-deploy`.
- Permissões: **Contents: Read and write**, **Actions: Read and write**.

### 0.4 Secrets da organização (valem para os 2 repos)
> Os repos devem ser **públicos**. Assim o ArgoCD lê o `solidarytech-deploy` sem credencial e o plano Free da org libera os org secrets. Se forem privados, use `gh secret set ... -R solidarytech-fiap/<repo>` em cada repo e cadastre o repo no ArgoCD com um token.

```bash
ORG=solidarytech-fiap
gh secret set TF_STATE_BUCKET --org $ORG --visibility all --body "solidarytech-tfstate-211125582187"
gh secret set GITOPS_TOKEN    --org $ORG --visibility all --body "<PAT do passo 0.3>"
gh secret set BUDGET_EMAILS   --org $ORG --visibility all --body '["seu-email@exemplo.com"]'
```

## 1. Início de cada sessão do AWS Academy

As credenciais expiram a cada sessão. Copie o bloco de **AWS Details > AWS CLI** para `~/.aws/credentials` e depois:
```bash
ORG=solidarytech-fiap
gh secret set AWS_ACCESS_KEY_ID     --org $ORG --visibility all --body "$(aws configure get aws_access_key_id)"
gh secret set AWS_SECRET_ACCESS_KEY --org $ORG --visibility all --body "$(aws configure get aws_secret_access_key)"
gh secret set AWS_SESSION_TOKEN     --org $ORG --visibility all --body "$(aws configure get aws_session_token)"
```
Rode o workflow **Preflight Check** (`solidarytech-app` > Actions). Ele precisa ficar todo verde.

## 2. Infraestrutura (Terraform)
Actions > **Terraform Apply (infra completa)** > `action=apply`, `trigger_argocd=true`.

Ordem executada: networking, security, data | platform | compute, finops (pode falhar no Academy sem bloquear), relatório de tags, disparo do ArgoCD.

## 3. Imagens (CI/CD)
Na primeira vez (o overlay ainda aponta para a tag `bootstrap`), dispare os 3 pipelines:
```bash
for s in ngo-service donation-service volunteer-service; do gh workflow run $s.yml -R solidarytech-fiap/solidarytech-app; done
```
Cada pipeline roda testes, lint, SAST, SCA, build, Trivy, push no ECR e commit da nova tag no `solidarytech-deploy`. O ArgoCD faz o deploy.

## 4. ArgoCD e plataforma
O workflow **Install ArgoCD + App-of-Apps** (`solidarytech-deploy`) é disparado pelo passo 2. O resumo dele mostra as URLs.
```bash
aws eks update-kubeconfig --name solidarytech-eks --region us-east-1
kubectl get applications -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## 5. Validação
```bash
ING=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
BASE_URL=http://$ING ./scripts/local/smoke-test.sh
BASE_URL=http://$ING DURATION=600 RPS=5 ./scripts/load-test.sh   # popula os dashboards
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
aws ssm get-parameter --name /solidarytech/prod/observability/grafana-admin --with-decryption --query Parameter.Value --output text
```

## 6. Datadog (semana 7, trial de 14 dias)
1. Criar a conta trial. Gerar a API key e a Application key.
2. Guardar no SSM (fora do Terraform, porque persistem entre destroys):
```bash
aws ssm put-parameter --name /solidarytech/prod/datadog/api-key --type SecureString --value '<API_KEY>'
aws ssm put-parameter --name /solidarytech/prod/datadog/app-key --type SecureString --value '<APP_KEY>'
aws ssm put-parameter --name /solidarytech/prod/datadog/site    --type String       --value 'datadoghq.com'
aws ssm put-parameter --name /solidarytech/prod/github/webhook-pat --type SecureString --value '<PAT com Actions: write>'
```
3. Ativar o exporter Datadog no Collector (GitOps):
```bash
cd ../solidarytech-deploy
git mv -f k8s/apps-optional/otel-collector-datadog.yaml k8s/apps/12-otel-collector.yaml
git mv k8s/apps-optional/14-datadog-secret.yaml k8s/apps/
git commit -m "feat(observability): ativa Datadog APM" && git push
```
4. Configurar JSM e Slack (`docs/itsm.md`, seção 7) e rodar **Datadog Terraform** com `apply`.
5. Confirmar o nome das métricas `trace.*` em Metrics Explorer e ajustar `trace_operation` se necessário.

## 7. Demonstrações
| Demo | Como |
|---|---|
| SLO / alerta / self-healing | `CHAOS_TOKEN=$(aws ssm get-parameter --name /solidarytech/prod/donation/chaos-token --with-decryption --query Parameter.Value --output text) BASE_URL=http://$ING ./scripts/chaos.sh on 0.3 0` |
| DR (Velero) | `solidarytech-deploy` > Actions > **DR Drill** > `confirm=drill` |
| Rightsizing | `./scripts/rightsizing-report.sh`, commit no overlay, ArgoCD |
| Tags | resumo do Terraform Apply e `./scripts/check-tags.sh` |

## 8. Fim da sessão (economia de créditos)
Actions > **Terraform Destroy** > `confirm=destroy`. Ele remove os Load Balancers do cluster antes de destruir a VPC.

O que persiste: bucket de state, SSM `/datadog/*` e `/github/*`, repos e secrets do GitHub.
