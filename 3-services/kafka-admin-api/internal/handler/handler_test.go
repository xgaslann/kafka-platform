package handler

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"kafka-admin-api/internal/model"
)

// Mock Kafka Client
type MockKafkaClient struct {
	mock.Mock
}

func (m *MockKafkaClient) ListBrokers(ctx context.Context) ([]model.Broker, error) {
	args := m.Called(ctx)
	return args.Get(0).([]model.Broker), args.Error(1)
}

func (m *MockKafkaClient) ListTopics(ctx context.Context) ([]model.Topic, error) {
	args := m.Called(ctx)
	return args.Get(0).([]model.Topic), args.Error(1)
}

func (m *MockKafkaClient) GetTopic(ctx context.Context, name string) (*model.TopicDetail, error) {
	args := m.Called(ctx, name)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*model.TopicDetail), args.Error(1)
}

func (m *MockKafkaClient) CreateTopic(ctx context.Context, req model.CreateTopicRequest) error {
	args := m.Called(ctx, req)
	return args.Error(0)
}

func (m *MockKafkaClient) UpdateTopicConfig(ctx context.Context, name string, configs map[string]string) error {
	args := m.Called(ctx, name, configs)
	return args.Error(0)
}

func (m *MockKafkaClient) ListConsumerGroups(ctx context.Context) ([]model.ConsumerGroup, error) {
	args := m.Called(ctx)
	return args.Get(0).([]model.ConsumerGroup), args.Error(1)
}

func (m *MockKafkaClient) GetConsumerGroup(ctx context.Context, groupID string) (*model.ConsumerGroupDetail, error) {
	args := m.Called(ctx, groupID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*model.ConsumerGroupDetail), args.Error(1)
}

func (m *MockKafkaClient) CreateConsumer(groupID, autoOffset string) (*kafka.Consumer, error) {
	args := m.Called(groupID, autoOffset)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*kafka.Consumer), args.Error(1)
}

func (m *MockKafkaClient) ConsumeMessages(ctx context.Context, topic, groupID, autoOffset string, maxMessages int, msgChan chan<- model.Message) error {
	args := m.Called(ctx, topic, groupID, autoOffset, maxMessages, msgChan)
	return args.Error(0)
}

func (m *MockKafkaClient) Close() {}

func setupTestApp(mockClient *MockKafkaClient) *fiber.App {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := NewWithClient(mockClient, logger)
	app := fiber.New()
	h.SetupRoutes(app)
	return app
}

func TestHealth(t *testing.T) {
	app := fiber.New()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := &Handler{logger: logger}
	app.Get("/health", h.health)

	req := httptest.NewRequest("GET", "/health", nil)
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
}

func TestListBrokers(t *testing.T) {
	mockClient := new(MockKafkaClient)
	mockClient.On("ListBrokers", mock.Anything).Return([]model.Broker{
		{ID: 1, Host: "broker-1", Port: 9092},
		{ID: 2, Host: "broker-2", Port: 9092},
	}, nil)

	app := setupTestApp(mockClient)

	req := httptest.NewRequest("GET", "/brokers", nil)
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	var brokers []model.Broker
	err = json.NewDecoder(resp.Body).Decode(&brokers)
	assert.NoError(t, err)
	assert.Len(t, brokers, 2)
	assert.Equal(t, int32(1), brokers[0].ID)
}

func TestListTopics(t *testing.T) {
	mockClient := new(MockKafkaClient)
	mockClient.On("ListTopics", mock.Anything).Return([]model.Topic{
		{Name: "topic-1", PartitionCount: 3, ReplicationFactor: 3},
	}, nil)

	app := setupTestApp(mockClient)

	req := httptest.NewRequest("GET", "/topics", nil)
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	var topics []model.Topic
	err = json.NewDecoder(resp.Body).Decode(&topics)
	assert.NoError(t, err)
	assert.Len(t, topics, 1)
	assert.Equal(t, "topic-1", topics[0].Name)
}

func TestCreateTopic(t *testing.T) {
	mockClient := new(MockKafkaClient)
	mockClient.On("CreateTopic", mock.Anything, mock.MatchedBy(func(req model.CreateTopicRequest) bool {
		return req.Name == "test-topic" && req.Partitions == 3
	})).Return(nil)

	app := setupTestApp(mockClient)

	body := `{"name": "test-topic", "partitions": 3, "replication_factor": 3}`
	req := httptest.NewRequest("POST", "/topics", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 201, resp.StatusCode)
}

func TestCreateTopicValidationError(t *testing.T) {
	mockClient := new(MockKafkaClient)
	app := setupTestApp(mockClient)

	body := `{"name": "", "partitions": 0}`
	req := httptest.NewRequest("POST", "/topics", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)
}

func TestGetTopic(t *testing.T) {
	mockClient := new(MockKafkaClient)
	mockClient.On("GetTopic", mock.Anything, "test-topic").Return(&model.TopicDetail{
		Name: "test-topic",
		Partitions: []model.Partition{
			{ID: 0, Leader: 1, Replicas: []int32{1, 2, 3}, ISR: []int32{1, 2, 3}},
		},
		Configs: map[string]string{"retention.ms": "604800000"},
	}, nil)

	app := setupTestApp(mockClient)

	req := httptest.NewRequest("GET", "/topics/test-topic", nil)
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	var topic model.TopicDetail
	err = json.NewDecoder(resp.Body).Decode(&topic)
	assert.NoError(t, err)
	assert.Equal(t, "test-topic", topic.Name)
}

func TestListConsumerGroups(t *testing.T) {
	mockClient := new(MockKafkaClient)
	mockClient.On("ListConsumerGroups", mock.Anything).Return([]model.ConsumerGroup{
		{GroupID: "group-1", State: "Stable"},
	}, nil)

	app := setupTestApp(mockClient)

	req := httptest.NewRequest("GET", "/consumer-groups", nil)
	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	var groups []model.ConsumerGroup
	err = json.NewDecoder(resp.Body).Decode(&groups)
	assert.NoError(t, err)
	assert.Len(t, groups, 1)
}
