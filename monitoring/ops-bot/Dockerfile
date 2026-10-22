# syntax=docker/dockerfile:1
# Build context: monitoring/ops-bot (its own Go module).
#   docker build -t ludo-arena-ops-bot monitoring/ops-bot
FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/ops-bot ./cmd/ops-bot

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/ops-bot /app/ops-bot
USER nonroot:nonroot
# /healthz, /metrics and the Alertmanager webhook; keep it on the private network.
EXPOSE 9097
# TELEGRAM_BOT_TOKEN and other secrets come from the orchestrator's environment.
ENTRYPOINT ["/app/ops-bot"]
