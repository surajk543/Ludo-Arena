# syntax=docker/dockerfile:1
# Build context: the bot-play/ directory (it is its own Go module).
#   docker build -t bot-play:1.0.0 --build-arg VERSION=1.0.0 --build-arg BUILD=1 bot-play
FROM golang:1.27.3-alpine AS build
ARG VERSION=1.0.0
ARG BUILD=1
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w -X ludoarena/botplay/internal/config.Version=${VERSION} -X ludoarena/botplay/internal/config.Build=${BUILD}" \
      -o /out/bot-play ./cmd/bot-play

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/bot-play /app/bot-play
COPY configs /app/configs
USER nonroot:nonroot
# Health + metrics (metrics.listen_addr); keep it cluster-internal.
EXPOSE 9091
# BOT_SERVICE_KEY must be provided by the orchestrator's secret store.
ENTRYPOINT ["/app/bot-play"]
CMD ["--config", "/app/configs/environments/production.yaml", "--profiles", "/app/configs/profiles.yaml"]
