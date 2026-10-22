# syntax=docker/dockerfile:1
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
ARG COMMIT=
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w \
      -X ludoarena/internal/buildinfo.Version=${VERSION} \
      -X ludoarena/internal/buildinfo.Commit=${COMMIT}" \
      -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
COPY config /app/config
USER nonroot:nonroot
EXPOSE 8080 9090
ENTRYPOINT ["/app/server"]
