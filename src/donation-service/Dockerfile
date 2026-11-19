# syntax=docker/dockerfile:1.7
# ---------- build ----------
FROM golang:1.26-alpine AS builder
WORKDIR /src

# Cache das dependencias separado do codigo (layer cache).
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Binario estatico e sem simbolos de debug.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/donation-service .

# ---------- runtime ----------
# distroless/static: sem shell nem gerenciador de pacotes (superficie minima),
# ja inclui CA certificates e roda como nonroot (UID 65532).
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/donation-service /app/donation-service
USER nonroot:nonroot
EXPOSE 8082
ENTRYPOINT ["/app/donation-service"]
