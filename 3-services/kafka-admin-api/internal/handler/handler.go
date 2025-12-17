package handler

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strconv"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/go-playground/validator/v10"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/fiber/v2/middleware/requestid"

	"kafka-admin-api/internal/model"
)

type KafkaClient interface {
	ListBrokers(ctx context.Context) ([]model.Broker, error)
	ListTopics(ctx context.Context) ([]model.Topic, error)
	GetTopic(ctx context.Context, name string) (*model.TopicDetail, error)
	CreateTopic(ctx context.Context, req model.CreateTopicRequest) error
	UpdateTopicConfig(ctx context.Context, name string, configs map[string]string) error
	ListConsumerGroups(ctx context.Context) ([]model.ConsumerGroup, error)
	GetConsumerGroup(ctx context.Context, groupID string) (*model.ConsumerGroupDetail, error)
	CreateConsumer(groupID, autoOffset string) (*kafka.Consumer, error)
	ConsumeMessages(ctx context.Context, topic, groupID, autoOffset string, maxMessages int, msgChan chan<- model.Message) error
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
	app.Get("/topics/:topicName/consume", h.consumeMessagesBatch)
	app.Get("/topics/:topicName/messages", h.consumeMessagesSSE)
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

func (h *Handler) consumeMessagesBatch(c *fiber.Ctx) error {
	topicName := c.Params("topicName")
	if topicName == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "topic name required"})
	}

	groupID := c.Query("group_id", "kafka-admin-api-batch-consumer")
	autoOffset := c.Query("offset", "earliest")
	maxMessagesStr := c.Query("max", "10")
	timeoutStr := c.Query("timeout", "5")

	maxMessages, _ := strconv.Atoi(maxMessagesStr)
	timeout, _ := strconv.Atoi(timeoutStr)

	if maxMessages <= 0 {
		maxMessages = 10
	}
	if timeout <= 0 {
		timeout = 5
	}

	h.logger.Info("starting batch consumer",
		"topic", topicName,
		"group_id", groupID,
		"offset", autoOffset,
		"max_messages", maxMessages,
		"timeout", timeout,
	)

	consumer, err := h.client.CreateConsumer(groupID, autoOffset)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}
	defer consumer.Close()

	if err := consumer.Subscribe(topicName, nil); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	messages := make([]model.Message, 0, maxMessages)
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	for len(messages) < maxMessages {
		select {
		case <-ctx.Done():
			goto done
		default:
			msg, err := consumer.ReadMessage(100 * time.Millisecond)
			if err != nil {
				if err.(kafka.Error).Code() == kafka.ErrTimedOut {
					continue
				}
				continue
			}

			headers := make(map[string]string)
			for _, hdr := range msg.Headers {
				headers[hdr.Key] = string(hdr.Value)
			}

			messages = append(messages, model.Message{
				Topic:     *msg.TopicPartition.Topic,
				Partition: msg.TopicPartition.Partition,
				Offset:    int64(msg.TopicPartition.Offset),
				Key:       string(msg.Key),
				Value:     string(msg.Value),
				Timestamp: msg.Timestamp.UnixMilli(),
				Headers:   headers,
			})
		}
	}

done:
	h.logger.Info("batch consumer finished", "messages", len(messages))
	return c.JSON(fiber.Map{
		"topic":    topicName,
		"group_id": groupID,
		"count":    len(messages),
		"messages": messages,
	})
}

func (h *Handler) consumeMessagesSSE(c *fiber.Ctx) error {
	topicName := c.Params("topicName")
	if topicName == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "topic name required"})
	}

	groupID := c.Query("group_id", "kafka-admin-api-sse-consumer")
	autoOffset := c.Query("offset", "earliest")
	maxMessagesStr := c.Query("max", "0")

	maxMessages, _ := strconv.Atoi(maxMessagesStr)

	h.logger.Info("starting SSE consumer",
		"topic", topicName,
		"group_id", groupID,
		"offset", autoOffset,
		"max_messages", maxMessages,
	)

	c.Set("Content-Type", "text/event-stream")
	c.Set("Cache-Control", "no-cache")
	c.Set("Connection", "keep-alive")
	c.Set("Transfer-Encoding", "chunked")

	// Capture variables for closure
	client := h.client
	logger := h.logger

	c.Context().SetBodyStreamWriter(func(w *bufio.Writer) {
		consumer, err := client.CreateConsumer(groupID, autoOffset)
		if err != nil {
			logger.Error("failed to create consumer", "error", err)
			fmt.Fprintf(w, "event: error\ndata: {\"error\": \"%s\"}\n\n", err.Error())
			w.Flush()
			return
		}
		defer consumer.Close()

		if err := consumer.Subscribe(topicName, nil); err != nil {
			logger.Error("failed to subscribe", "error", err)
			fmt.Fprintf(w, "event: error\ndata: {\"error\": \"%s\"}\n\n", err.Error())
			w.Flush()
			return
		}

		logger.Info("SSE consumer subscribed", "topic", topicName)

		count := 0
		for {
			msg, err := consumer.ReadMessage(500 * time.Millisecond)
			if err != nil {
				if err.(kafka.Error).Code() == kafka.ErrTimedOut {
					// Send heartbeat
					fmt.Fprintf(w, ": heartbeat\n\n")
					if err := w.Flush(); err != nil {
						logger.Info("client disconnected")
						return
					}
					continue
				}
				logger.Error("read error", "error", err)
				continue
			}

			headers := make(map[string]string)
			for _, hdr := range msg.Headers {
				headers[hdr.Key] = string(hdr.Value)
			}

			m := model.Message{
				Topic:     *msg.TopicPartition.Topic,
				Partition: msg.TopicPartition.Partition,
				Offset:    int64(msg.TopicPartition.Offset),
				Key:       string(msg.Key),
				Value:     string(msg.Value),
				Timestamp: msg.Timestamp.UnixMilli(),
				Headers:   headers,
			}

			data, _ := json.Marshal(m)
			fmt.Fprintf(w, "event: message\ndata: %s\n\n", data)
			if err := w.Flush(); err != nil {
				logger.Info("client disconnected during write")
				return
			}

			count++
			logger.Info("SSE message sent", "count", count, "offset", m.Offset)

			if maxMessages > 0 && count >= maxMessages {
				fmt.Fprintf(w, "event: done\ndata: {\"total_messages\": %d}\n\n", count)
				w.Flush()
				logger.Info("SSE max messages reached", "count", count)
				return
			}
		}
	})

	return nil
}
