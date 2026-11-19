#!/bin/sh
# Executado pelo LocalStack quando fica pronto: cria fila e tabela iguais as da AWS.
set -e
awslocal sqs create-queue --queue-name solidary-donations
awslocal dynamodb create-table \
  --table-name SolidaryTechVolunteers \
  --attribute-definitions AttributeName=volunteer_id,AttributeType=S AttributeName=ngo_id,AttributeType=N \
  --key-schema AttributeName=volunteer_id,KeyType=HASH \
  --global-secondary-indexes 'IndexName=ngo_id-index,KeySchema=[{AttributeName=ngo_id,KeyType=HASH}],Projection={ProjectionType=ALL}' \
  --billing-mode PAY_PER_REQUEST
