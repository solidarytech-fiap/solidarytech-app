package main

import (
	"context"
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

const serviceName = "donation-service"

func main() {
	_ = godotenv.Load()

	// Logs estruturados em JSON (Loki/Datadog fazem parse automatico).
	logger := slog.New(traceHandler{slog.NewJSONHandler(os.Stdout, nil)}).With("service", serviceName)
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownOTel, err := initOTel(ctx, serviceName)
	if err != nil {
		slog.Error("falha ao iniciar OpenTelemetry", "error", err)
		os.Exit(1)
	}

	port := getenv("PORT", "8082")

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		slog.Error("DATABASE_URL e obrigatoria")
		os.Exit(1)
	}

	db, err := openDB(dbURL)
	if err != nil {
		slog.Error("erro ao conectar ao banco de dados", "error", err)
		os.Exit(1)
	}
	slog.Info("conectado ao PostgreSQL")

	var sqsSvc SQSSender
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		cfg := &aws.Config{Region: aws.String(region)}
		// Permite LocalStack no ambiente local (docker compose).
		if ep := os.Getenv("AWS_ENDPOINT_URL"); ep != "" {
			cfg.Endpoint = aws.String(ep)
		}
		sess, err := session.NewSession(cfg)
		if err != nil {
			slog.Error("erro ao criar sessao AWS", "error", err)
			os.Exit(1)
		}
		sqsSvc = sqs.New(sess)
		slog.Info("integracao com AWS SQS ativada", "queue", queueURL)
	}

	app := NewApp(db, sqsSvc, queueURL, os.Getenv("CHAOS_TOKEN"))

	srv := &http.Server{
		Addr: ":" + port,
		Handler: otelhttp.NewHandler(app.Routes(promhttp.Handler()), serviceName,
			// Probes e scrape nao geram spans (ruido e custo no APM).
			otelhttp.WithFilter(func(r *http.Request) bool {
				switch r.URL.Path {
				case "/health", "/ready", "/metrics":
					return false
				}
				return true
			}),
		),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		slog.Info("donation-service iniciado", "port", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("erro no servidor HTTP", "error", err)
			os.Exit(1)
		}
	}()

	// Graceful shutdown: o Kubernetes envia SIGTERM antes de matar o pod.
	<-ctx.Done()
	slog.Info("sinal de parada recebido, encerrando")
	app.SetReady(false)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("erro no shutdown HTTP", "error", err)
	}
	app.Wait()
	_ = db.Close()
	_ = shutdownOTel(shutdownCtx)
	slog.Info("encerrado")
}

func openDB(url string) (*sql.DB, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return nil, err
	}
	return db, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
