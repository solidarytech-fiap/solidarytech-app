"""Logs estruturados em JSON (um objeto por linha) para Loki/Datadog."""
import json
import logging
import sys


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str):
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "time": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "service": self.service,
            "msg": record.getMessage(),
            "logger": record.name,
        }
        # Injetados pela instrumentacao OTel de logging (correlacao log <-> trace).
        trace_id = getattr(record, "otelTraceID", "0")
        if trace_id and trace_id != "0":
            payload["trace_id"] = trace_id
            payload["span_id"] = getattr(record, "otelSpanID", "")
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def setup_logging(service: str) -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(service))
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    return logging.getLogger(service)
