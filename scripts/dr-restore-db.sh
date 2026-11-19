#!/usr/bin/env bash
# Restaura o ultimo dump logico (S3 us-west-2) em um PostgreSQL de destino.
# Usado no failover regional (docs/runbooks/dr-regional-failover.md) ou para
# validar o backup (restore em banco temporario).
#
# Uso: DB=donation_db TARGET_URL='postgres://user:pass@host:5432/donation_db?sslmode=require' \
#      ./scripts/dr-restore-db.sh [s3-key opcional]
set -euo pipefail
DB="${DB:-donation_db}"
TARGET_URL="${TARGET_URL:?defina TARGET_URL}"
REGION="${BACKUP_REGION:-us-west-2}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${BACKUP_BUCKET:-solidarytech-dr-backups-$ACCOUNT}"
KEY="${1:-postgres/$DB/latest.dump}"

echo "Baixando s3://$BUCKET/$KEY ($REGION)..."
aws s3 cp "s3://$BUCKET/$KEY" "/tmp/$DB.dump" --region "$REGION"
aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query LastModified --output text \
  | xargs -I{} echo "Ponto de recuperacao (RPO): {}"

echo "Restaurando em $(echo "$TARGET_URL" | sed 's#//[^@]*@#//***@#')..."
pg_restore --clean --if-exists --no-owner --dbname="$TARGET_URL" "/tmp/$DB.dump"
psql "$TARGET_URL" -c "SELECT count(*) AS registros FROM donations;" 2>/dev/null || true
echo "Restore concluido."
