import os
import sys
import time
import uuid

import boto3
from boto3.dynamodb.conditions import Attr, Key
from dotenv import load_dotenv
from flask import Flask, jsonify, request

from logging_config import setup_logging
from metrics import init_metrics

SERVICE = "volunteer-service"
log = setup_logging(SERVICE)

load_dotenv()

app = Flask(__name__)
init_metrics(app, SERVICE)

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE")
# GSI criado pelo Terraform. Sem ele (ex: ambiente local), cai no Scan.
NGO_INDEX = os.getenv("AWS_DYNAMODB_NGO_INDEX", "")
AWS_ENDPOINT_URL = os.getenv("AWS_ENDPOINT_URL") or None  # LocalStack

if not DYNAMODB_TABLE:
    log.critical("AWS_DYNAMODB_TABLE nao definida.")
    sys.exit(1)

try:
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION, endpoint_url=AWS_ENDPOINT_URL)
    table = dynamodb.Table(DYNAMODB_TABLE)
    log.info(f"Conectado a tabela DynamoDB: {DYNAMODB_TABLE}")
except Exception as e:
    log.critical(f"Falha ao conectar no DynamoDB: {e}")
    sys.exit(1)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


@app.route("/ready")
def ready():
    try:
        table.load()  # DescribeTable
        return jsonify({"status": "ready"})
    except Exception:
        return jsonify({"status": "dynamodb_unavailable"}), 503


@app.route("/volunteers", methods=["POST"])
def register_volunteer():
    data = request.get_json(silent=True)
    if not data or not all(k in data for k in ("name", "email", "ngo_id")):
        return jsonify({"error": "Campos obrigatorios ausentes"}), 400
    try:
        ngo_id = int(data["ngo_id"])
    except (TypeError, ValueError):
        return jsonify({"error": "ngo_id invalido"}), 400

    item = {
        "volunteer_id": str(uuid.uuid4()),
        "name": data["name"],
        "email": data["email"],
        "ngo_id": ngo_id,
        "registered_at": str(int(time.time())),
    }
    try:
        table.put_item(Item=item)
        return jsonify(item), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntario no DynamoDB: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route("/volunteers/<int:ngo_id>", methods=["GET"])
def get_volunteers_by_ngo(ngo_id):
    try:
        if NGO_INDEX:
            # Query no GSI: custo proporcional ao resultado (FinOps).
            response = table.query(IndexName=NGO_INDEX, KeyConditionExpression=Key("ngo_id").eq(ngo_id))
        else:
            response = table.scan(FilterExpression=Attr("ngo_id").eq(ngo_id))
        items = response.get("Items", [])
        for i in items:
            i["ngo_id"] = int(i["ngo_id"])
        return jsonify(items), 200
    except Exception as e:
        log.error(f"Erro ao buscar dados no DynamoDB: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8083))
    app.run(host="0.0.0.0", port=port)  # nosec B104 - container
