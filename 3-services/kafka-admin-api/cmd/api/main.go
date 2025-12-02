package main

import (
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"kafka-admin-api/internal/config"
	"kafka-admin-api/internal/handler"
	"kafka-admin-api/internal/kafka"

	"github.com/gofiber/fiber/v2"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.Load()
	if err != nil {
		logger.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	kafkaClient, err := kafka.NewClient(kafka.Config{
		BootstrapServers: cfg.BootstrapServers,
		Username:         cfg.SASLUsername,
		Password:         cfg.SASLPassword,
		CALocation:       cfg.CALocation,
	}, logger)
	if err != nil {
		logger.Error("failed to create kafka client", "error", err)
		os.Exit(1)
	}
	defer kafkaClient.Close()

	app := fiber.New(fiber.Config{
		AppName: "kafka-admin-api",
	})

	h := handler.New(kafkaClient, logger)
	h.SetupRoutes(app)

	// Graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		logger.Info("shutting down server")
		if err := app.Shutdown(); err != nil {
			logger.Error("shutdown error", "error", err)
		}
	}()

	logger.Info("starting server", "port", cfg.Port)
	if err := app.Listen(":" + cfg.Port); err != nil {
		logger.Error("server error", "error", err)
		os.Exit(1)
	}
}
