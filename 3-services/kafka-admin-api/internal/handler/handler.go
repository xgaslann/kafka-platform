package handler

import (
	"context"
	"log/slog"

	"github.com/go-playground/validator/v10"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/fiber/v2/middleware/requestid"

	"kafka-admin-api/internal/model"
)

// KafkaClient interface for testing
type KafkaClient interface {
	ListBrokers(ctx context.Context) ([]model.Broker, error)
	ListTopics(ctx context.Context) ([]model.Topic, error)
	GetTopic(ctx context.Context, name string) (*model.TopicDetail, error)
	CreateTopic(ctx context.Context, req model.CreateTopicRequest) error
	UpdateTopicConfig(ctx context.Context, name string, configs map[string]string) error
	ListConsumerGroups(ctx context.Context) ([]model.ConsumerGroup, error)
	GetConsumerGroup(ctx context.Context, groupID string) (*model.ConsumerGroupDetail, error)
	Close()
}

type Handler struct {
	client   KafkaClient
	logger   *slog.Logger
	validate *validator.Validate
}

func New(client KafkaClient, logger *slog.Logger) *Handler {
	return &Handler{
		client:   client,
		logger:   logger,
		validate: validator.New(),
	}
}

// NewWithClient alias for testing
func NewWithClient(client KafkaClient, logger *slog.Logger) *Handler {
	return New(client, logger)
}

func (h *Handler) SetupRoutes(app *fiber.App) {
	app.Use(recover.New())
	app.Use(requestid.New())
	app.Use(h.loggingMiddleware)

	app.Get("/health", h.health)
	app.Get("/brokers", h.listBrokers)
	app.Get("/topics", h.listTopics)
	app.Post("/topics", h.createTopic)
	app.Get("/topics/:topicName", h.getTopic)
	app.Put("/topics/:topicName", h.updateTopic)
	app.Get("/consumer-groups", h.listConsumerGroups)
	app.Get("/consumer-groups/:groupID", h.getConsumerGroup)
}

func (h *Handler) loggingMiddleware(c *fiber.Ctx) error {
	h.logger.Info("request",
		"method", c.Method(),
		"path", c.Path(),
		"request_id", c.Locals("requestid"),
	)
	return c.Next()
}

func (h *Handler) health(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{"status": "healthy"})
}

func (h *Handler) listBrokers(c *fiber.Ctx) error {
	brokers, err := h.client.ListBrokers(c.Context())
	if err != nil {
		h.logger.Error("list brokers failed", "error", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(brokers)
}

func (h *Handler) listTopics(c *fiber.Ctx) error {
	topics, err := h.client.ListTopics(c.Context())
	if err != nil {
		h.logger.Error("list topics failed", "error", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(topics)
}

func (h *Handler) getTopic(c *fiber.Ctx) error {
	topicName := c.Params("topicName")
	if topicName == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "topic name required"})
	}

	topic, err := h.client.GetTopic(c.Context(), topicName)
	if err != nil {
		h.logger.Error("get topic failed", "topic", topicName, "error", err)
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(topic)
}

func (h *Handler) createTopic(c *fiber.Ctx) error {
	var req model.CreateTopicRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.validate.Struct(req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	if err := h.client.CreateTopic(c.Context(), req); err != nil {
		h.logger.Error("create topic failed", "topic", req.Name, "error", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{"message": "topic created"})
}

func (h *Handler) updateTopic(c *fiber.Ctx) error {
	topicName := c.Params("topicName")
	if topicName == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "topic name required"})
	}

	var req model.UpdateTopicRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if len(req.Configs) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "configs required"})
	}

	if err := h.client.UpdateTopicConfig(c.Context(), topicName, req.Configs); err != nil {
		h.logger.Error("update topic failed", "topic", topicName, "error", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"message": "topic config updated"})
}

func (h *Handler) listConsumerGroups(c *fiber.Ctx) error {
	groups, err := h.client.ListConsumerGroups(c.Context())
	if err != nil {
		h.logger.Error("list consumer groups failed", "error", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(groups)
}

func (h *Handler) getConsumerGroup(c *fiber.Ctx) error {
	groupID := c.Params("groupID")
	if groupID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "group id required"})
	}

	group, err := h.client.GetConsumerGroup(c.Context(), groupID)
	if err != nil {
		h.logger.Error("get consumer group failed", "group", groupID, "error", err)
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(group)
}
