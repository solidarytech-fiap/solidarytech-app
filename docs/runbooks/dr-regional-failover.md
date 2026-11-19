# Runbook - Failover regional (perda de us-east-1) - Cenário C6 do PCN

**Objetivo:** voltar a receber doações em **us-west-2** em até 4 h, com perda máxima de 15 min de doações.

**Pré-requisitos já existentes em us-west-2:** bucket `solidarytech-dr-backups-<conta>` com dumps (`postgres/*/latest.dump`) e backups do Velero, e réplica das imagens no ECR.

## 1. Declarar o desastre e comunicar
Ver `pcn.md`, seção 5. Abrir o incidente SEV1 no JSM.

## 2. Subir a infraestrutura em us-west-2 (IaC, mesmos módulos)
As camadas são parametrizadas por região. Use outro state key para não tocar no state da região primária:

```bash
export TF_STATE_BUCKET=solidarytech-tfstate-<conta>   # o bucket fica em us-east-1; em perda total, criar um novo com terraform/bootstrap em us-west-2
for layer in networking security data compute; do
  (cd terraform/environments/prod/$layer && \
   terraform init -reconfigure -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=us-east-1" \
     -backend-config="key=dr/$layer/terraform.tfstate" && \
   terraform apply -auto-approve -var aws_region=us-west-2 -var dr_region=us-east-1 -var tf_state_bucket=$TF_STATE_BUCKET)
done
```
> As camadas `data` e `compute` leem o remote state `prod/networking`. No modo DR, ajuste o `key` do `terraform_remote_state` para `dr/networking/terraform.tfstate` (ou exporte uma variável de prefixo). Esse é o próximo passo de evolução para a Opção B (warm standby em 1 comando).

## 3. Restaurar os dados de doação
```bash
DB=donation_db TARGET_URL="$(aws ssm get-parameter --region us-west-2 --with-decryption \
  --name /solidarytech/prod/donation/db-connection --query Parameter.Value --output text | jq -r .url)" \
  ./scripts/dr-restore-db.sh
DB=ngo_db TARGET_URL="..." ./scripts/dr-restore-db.sh
```
O script mostra o `LastModified` do dump: esse é o **ponto de recuperação (RPO real)**.

## 4. Subir as aplicações
1. ArgoCD: `argocd-install.yml` com `CLUSTER_NAME`/`AWS_REGION` de us-west-2.
2. No `solidarytech-deploy`, aponte as imagens para `<conta>.dkr.ecr.us-west-2.amazonaws.com/...` e o `ClusterSecretStore` para `region: us-west-2`.
3. Opcional: `velero restore create --from-backup <ultimo-backup>` para trazer o estado não versionado.

## 5. Validar e reabrir
- `BASE_URL=http://<novo-elb> ./scripts/local/smoke-test.sh`
- Atualizar o DNS público para o novo Load Balancer.
- Registrar no incidente o RTO e o RPO reais.

## 6. Failback
Em janela planejada: backup final em us-west-2, restore em us-east-1, troca de DNS e destroy do ambiente DR.
