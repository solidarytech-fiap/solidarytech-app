package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Golden Metrics (RED) expostas em /metrics.
// Os nomes sao padronizados nos 3 servicos para que os dashboards e as
// recording rules de SLO usem a mesma query.
var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total de requisicoes HTTP.",
	}, []string{"service", "method", "route", "code"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_request_duration_seconds",
		Help: "Latencia das requisicoes HTTP.",
		// 0.3 e o limiar do SLI de latencia do donation-service.
		Buckets: []float64{0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5},
	}, []string{"service", "method", "route"})

	httpInFlight = promauto.NewGauge(prometheus.GaugeOpts{
		Name:        "http_requests_in_flight",
		Help:        "Requisicoes em andamento (saturacao).",
		ConstLabels: prometheus.Labels{"service": serviceName},
	})

	donationsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "donations_created_total",
		Help: "Doacoes criadas por status.",
	}, []string{"status"})

	donationsAmount = promauto.NewCounter(prometheus.CounterOpts{
		Name: "donations_amount_brl_total",
		Help: "Soma dos valores doados (BRL).",
	})

	sqsPublishTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sqs_publish_total",
		Help: "Publicacoes no SQS por resultado.",
	}, []string{"result"})
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// knownRoutes evita explosao de cardinalidade no label "route".
var knownRoutes = map[string]bool{
	"/health": true, "/ready": true, "/donations": true, "/admin/chaos": true, "/metrics": true,
}

func instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := r.URL.Path
		if !knownRoutes[route] {
			route = "other"
		}
		// Nao mede probes nem o proprio scrape (distorcem o SLI).
		if route == "/metrics" || route == "/health" || route == "/ready" {
			next.ServeHTTP(w, r)
			return
		}
		httpInFlight.Inc()
		defer httpInFlight.Dec()

		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		httpRequestDuration.WithLabelValues(serviceName, r.Method, route).Observe(time.Since(start).Seconds())
		httpRequestsTotal.WithLabelValues(serviceName, r.Method, route, strconv.Itoa(rec.status)).Inc()
	})
}
