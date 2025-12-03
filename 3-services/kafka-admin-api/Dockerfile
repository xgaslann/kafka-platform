FROM golang:1.25-alpine AS builder

RUN apk add --no-cache gcc musl-dev librdkafka-dev pkgconf

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=1 go build -tags musl -o kafka-admin-api ./cmd/api

FROM alpine:3.22

RUN apk add --no-cache librdkafka ca-certificates

WORKDIR /app

COPY --from=builder /app/kafka-admin-api .

EXPOSE 2020

CMD ["./kafka-admin-api"]