package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/service/sqs"
)

// Donation representa uma doacao.
type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// SQSSender e a interface minima do cliente SQS (facilita testes).
type SQSSender interface {
	SendMessageWithContext(aws.Context, *sqs.SendMessageInput, ...request.Option) (*sqs.SendMessageOutput, error)
}

// ChaosConfig permite injetar falhas em runtime para demonstrar
// SLO / Error Budget / alertas / self-healing. Fica so em memoria:
// um rollout restart (self-healing) zera a injecao.
type ChaosConfig struct {
	ErrorRate float64 `json:"error_rate"` // 0.0 a 1.0
	LatencyMS int     `json:"latency_ms"`
}

type App struct {
	DB         *sql.DB
	SQS        SQSSender
	QueueURL   string
	chaosToken string
	chaosMu    sync.RWMutex
	chaos      ChaosConfig
	ready      atomic.Bool
	wg         sync.WaitGroup
}

func NewApp(db *sql.DB, s SQSSender, queueURL, chaosToken string) *App {
	a := &App{DB: db, SQS: s, QueueURL: queueURL, chaosToken: chaosToken}
	a.ready.Store(true)
	return a
}

func (a *App) SetReady(v bool) { a.ready.Store(v) }

// Wait aguarda os envios SQS em andamento (graceful shutdown).
func (a *App) Wait() { a.wg.Wait() }

func (a *App) Routes(metricsHandler http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.HealthHandler)
	mux.HandleFunc("/ready", a.ReadyHandler)
	mux.HandleFunc("/donations", a.DonationHandler)
	mux.HandleFunc("/admin/chaos", a.ChaosHandler)
	if metricsHandler != nil {
		mux.Handle("/metrics", metricsHandler)
	}
	return instrument(mux)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (a *App) HealthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": serviceName})
}

// ReadyHandler verifica dependencias. Usado na readinessProbe.
func (a *App) ReadyHandler(w http.ResponseWriter, r *http.Request) {
	if !a.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "shutting_down"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.DB.PingContext(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db_unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *App) applyChaos(w http.ResponseWriter) bool {
	a.chaosMu.RLock()
	c := a.chaos
	a.chaosMu.RUnlock()
	if c.LatencyMS > 0 {
		time.Sleep(time.Duration(c.LatencyMS) * time.Millisecond)
	}
	// #nosec G404 -- aleatoriedade nao criptografica (apenas injecao de falhas)
	if c.ErrorRate > 0 && rand.Float64() < c.ErrorRate {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "falha injetada (chaos)"})
		return true
	}
	return false
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		if a.applyChaos(w) {
			return
		}
		a.createDonation(w, r)
	case http.MethodGet:
		if a.applyChaos(w) {
			return
		}
		a.listDonations(w, r)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Metodo nao permitido"})
	}
}

func (a *App) createDonation(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var d Donation
	if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Payload invalido"})
		return
	}
	if d.NgoID <= 0 || d.Amount <= 0 || d.DonorName == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ngo_id, amount (>0) e donor_name sao obrigatorios"})
		return
	}

	d.Status = "APPROVED" // simulacao de gateway de pagamento
	err := a.DB.QueryRowContext(r.Context(),
		"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
		d.NgoID, d.Amount, d.DonorName, d.Status,
	).Scan(&d.ID, &d.CreatedAt)
	if err != nil {
		slog.ErrorContext(r.Context(), "erro ao salvar doacao", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Erro interno"})
		return
	}
	donationsTotal.WithLabelValues(d.Status).Inc()
	donationsAmount.Add(d.Amount)

	if a.SQS != nil {
		a.wg.Add(1)
		go func(d Donation) {
			defer a.wg.Done()
			a.sendNotificationEvent(d)
		}(d)
	}

	writeJSON(w, http.StatusCreated, d)
}

func (a *App) listDonations(w http.ResponseWriter, r *http.Request) {
	limit := 100
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 1000 {
		limit = v
	}
	rows, err := a.DB.QueryContext(r.Context(),
		"SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC LIMIT $1", limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "erro ao listar doacoes", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Erro interno"})
		return
	}
	defer rows.Close()

	donations := []Donation{}
	for rows.Next() {
		var d Donation
		if err := rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Erro interno"})
			return
		}
		donations = append(donations, d)
	}
	writeJSON(w, http.StatusOK, donations)
}

// ChaosHandler: GET retorna a config atual; POST altera.
// Exige header X-Chaos-Token igual a env CHAOS_TOKEN (desligado se vazio).
func (a *App) ChaosHandler(w http.ResponseWriter, r *http.Request) {
	if a.chaosToken == "" || r.Header.Get("X-Chaos-Token") != a.chaosToken {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	switch r.Method {
	case http.MethodGet:
		a.chaosMu.RLock()
		defer a.chaosMu.RUnlock()
		writeJSON(w, http.StatusOK, a.chaos)
	case http.MethodPost:
		var c ChaosConfig
		if err := json.NewDecoder(r.Body).Decode(&c); err != nil || c.ErrorRate < 0 || c.ErrorRate > 1 || c.LatencyMS < 0 || c.LatencyMS > 10000 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "error_rate 0..1, latency_ms 0..10000"})
			return
		}
		a.chaosMu.Lock()
		a.chaos = c
		a.chaosMu.Unlock()
		slog.Warn("chaos atualizado", "error_rate", c.ErrorRate, "latency_ms", c.LatencyMS)
		writeJSON(w, http.StatusOK, c)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Metodo nao permitido"})
	}
}

// sendNotificationEvent publica no SQS com retry exponencial simples.
func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	input := &sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(a.QueueURL),
	}
	backoff := 200 * time.Millisecond
	for attempt := 1; attempt <= 3; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_, err := a.SQS.SendMessageWithContext(ctx, input)
		cancel()
		if err == nil {
			sqsPublishTotal.WithLabelValues("success").Inc()
			return
		}
		slog.Warn("falha ao publicar evento SQS", "attempt", attempt, "error", err)
		time.Sleep(backoff)
		backoff *= 2
	}
	sqsPublishTotal.WithLabelValues("failure").Inc()
	slog.Error("evento SQS descartado apos 3 tentativas", "donation_id", d.ID)
}
