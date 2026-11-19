# syntax=docker/dockerfile:1.7
# ---------- build: instala dependencias em um virtualenv ----------
FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --upgrade pip setuptools && pip install -r requirements.txt

# ---------- runtime: so o venv + codigo, usuario nao-root ----------
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH="/opt/venv/bin:$PATH" PORT=8083
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app app.py metrics.py logging_config.py ./
USER 10001
EXPOSE 8083
# 1 worker + threads: mantem o registry Prometheus em um unico processo.
# graceful-timeout: termina requisicoes em andamento no SIGTERM.
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8083", "--worker-class", "gthread", "--workers", "1", "--threads", "8", "--graceful-timeout", "20", "--access-logfile", "-", "app:app"]
