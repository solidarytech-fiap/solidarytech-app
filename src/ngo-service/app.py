import os
import sys

import psycopg2
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool

from logging_config import setup_logging
from metrics import init_metrics

SERVICE = "ngo-service"
log = setup_logging(SERVICE)

load_dotenv()

app = Flask(__name__)
init_metrics(app, SERVICE)

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("DATABASE_URL nao definida.")
    sys.exit(1)

try:
    # ThreadedConnectionPool: gunicorn roda com threads (gthread).
    pool = ThreadedConnectionPool(1, 10, dsn=DATABASE_URL)
    log.info("Pool de conexoes com o PostgreSQL inicializado.")
except Exception as e:
    log.critical(f"Erro ao conectar ao PostgreSQL: {e}")
    sys.exit(1)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


@app.route("/ready")
def ready():
    conn = None
    try:
        conn = pool.getconn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify({"status": "ready"})
    except Exception:
        return jsonify({"status": "db_unavailable"}), 503
    finally:
        if conn is not None:
            pool.putconn(conn)


@app.route("/ngos", methods=["POST"])
def create_ngo():
    data = request.get_json(silent=True)
    if not data or not all(k in data for k in ("name", "email", "cause", "city")):
        return jsonify({"error": "Campos obrigatorios ausentes"}), 400

    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO ngos (name, email, cause, city) VALUES (%s, %s, %s, %s) RETURNING *",
                (data["name"], data["email"], data["cause"], data["city"]),
            )
            new_ngo = cur.fetchone()
            conn.commit()
            return jsonify(new_ngo), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        return jsonify({"error": "E-mail ja cadastrado"}), 409
    except Exception as e:
        conn.rollback()
        log.error(f"Erro ao criar ONG: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route("/ngos", methods=["GET"])
def get_ngos():
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM ngos ORDER BY id DESC LIMIT 500")
            return jsonify(cur.fetchall()), 200
    except Exception as e:
        log.error(f"Erro ao buscar ONGs: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8081))
    app.run(host="0.0.0.0", port=port)  # nosec B104 - container
