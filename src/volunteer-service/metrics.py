"""Golden Metrics (RED) padronizadas entre os 3 servicos.

Mesmos nomes do donation-service (Go): http_requests_total e
http_request_duration_seconds, com labels service/method/route/code.
Gunicorn roda com 1 worker + threads para o registry ficar em um processo.
"""
import time

from flask import Flask, Response, g, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

REQUESTS = Counter(
    "http_requests_total", "Total de requisicoes HTTP.", ["service", "method", "route", "code"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latencia das requisicoes HTTP.",
    ["service", "method", "route"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5),
)
IN_FLIGHT = Gauge("http_requests_in_flight", "Requisicoes em andamento.", ["service"])

_SKIP = {"/metrics", "/health", "/ready"}


def init_metrics(app: Flask, service: str) -> None:
    @app.before_request
    def _start():
        if request.path in _SKIP:
            return
        g._start = time.perf_counter()
        IN_FLIGHT.labels(service).inc()

    @app.after_request
    def _record(response):
        start = g.pop("_start", None)
        if start is None:
            return response
        # url_rule evita alta cardinalidade (/volunteers/<int:ngo_id>).
        route = request.url_rule.rule if request.url_rule else "other"
        LATENCY.labels(service, request.method, route).observe(time.perf_counter() - start)
        REQUESTS.labels(service, request.method, route, str(response.status_code)).inc()
        IN_FLIGHT.labels(service).dec()
        return response

    @app.route("/metrics")
    def _metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
