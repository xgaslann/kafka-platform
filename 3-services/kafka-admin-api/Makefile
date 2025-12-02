.PHONY: build run test lint clean docker-build docker-push

APP_NAME := kafka-admin-api
VERSION := 1.0.0
DOCKER_REGISTRY :=
DOCKER_IMAGE := $(APP_NAME):$(VERSION)

build:
	go build -o bin/$(APP_NAME) ./cmd/api

run:
	go run ./cmd/api

test:
	go test -v ./...

test-coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

lint:
	golangci-lint run

clean:
	rm -rf bin/ coverage.out coverage.html

docker-build:
	docker build -t $(DOCKER_IMAGE) .

docker-run:
	docker run -p 2020:2020 \
		-e KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
		$(DOCKER_IMAGE)

# Development helpers
dev:
	KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
	go run ./cmd/api

tidy:
	go mod tidy

fmt:
	go fmt ./...