package kafka

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"

	"kafka-admin-api/internal/model"
)

type Config struct {
	BootstrapServers string
	Username         string
	Password         string
	CALocation       string
}

type Client struct {
	admin  *kafka.AdminClient
	logger *slog.Logger
}

func NewClient(cfg Config, logger *slog.Logger) (*Client, error) {
	config := &kafka.ConfigMap{
		"bootstrap.servers": cfg.BootstrapServers,
	}

	// Add security config only if SASL credentials provided
	if cfg.Username != "" && cfg.Password != "" {
		_ = config.SetKey("security.protocol", "SASL_SSL")
		_ = config.SetKey("sasl.mechanisms", "SCRAM-SHA-512")
		_ = config.SetKey("sasl.username", cfg.Username)
		_ = config.SetKey("sasl.password", cfg.Password)
		if cfg.CALocation != "" {
			_ = config.SetKey("ssl.ca.location", cfg.CALocation)
		}
	}

	admin, err := kafka.NewAdminClient(config)
	if err != nil {
		return nil, fmt.Errorf("create admin client: %w", err)
	}

	logger.Info("kafka admin client created", "bootstrap_servers", cfg.BootstrapServers)
	return &Client{admin: admin, logger: logger}, nil
}

func (c *Client) Close() {
	c.admin.Close()
	c.logger.Info("kafka admin client closed")
}

func (c *Client) ListBrokers(_ context.Context) ([]model.Broker, error) {
	metadata, err := c.admin.GetMetadata(nil, true, 10000)
	if err != nil {
		return nil, fmt.Errorf("get metadata: %w", err)
	}

	brokers := make([]model.Broker, 0, len(metadata.Brokers))
	for _, b := range metadata.Brokers {
		brokers = append(brokers, model.Broker{
			ID:   b.ID,
			Host: b.Host,
			Port: int32(b.Port),
		})
	}
	return brokers, nil
}

func (c *Client) ListTopics(_ context.Context) ([]model.Topic, error) {
	metadata, err := c.admin.GetMetadata(nil, true, 10000)
	if err != nil {
		return nil, fmt.Errorf("get metadata: %w", err)
	}

	topics := make([]model.Topic, 0)
	for name, t := range metadata.Topics {
		if len(name) > 0 && name[0] == '_' {
			continue
		}
		rf := 0
		if len(t.Partitions) > 0 {
			rf = len(t.Partitions[0].Replicas)
		}
		topics = append(topics, model.Topic{
			Name:              name,
			PartitionCount:    len(t.Partitions),
			ReplicationFactor: rf,
		})
	}
	return topics, nil
}

func (c *Client) GetTopic(ctx context.Context, name string) (*model.TopicDetail, error) {
	metadata, err := c.admin.GetMetadata(&name, false, 10000)
	if err != nil {
		return nil, fmt.Errorf("get metadata: %w", err)
	}

	t, exists := metadata.Topics[name]
	if !exists {
		return nil, fmt.Errorf("topic %s not found", name)
	}

	partitions := make([]model.Partition, 0, len(t.Partitions))
	for _, p := range t.Partitions {
		partitions = append(partitions, model.Partition{
			ID:       p.ID,
			Leader:   p.Leader,
			Replicas: p.Replicas,
			ISR:      p.Isrs,
		})
	}

	configResource := kafka.ConfigResource{
		Type: kafka.ResourceTopic,
		Name: name,
	}
	results, err := c.admin.DescribeConfigs(ctx, []kafka.ConfigResource{configResource})
	if err != nil {
		return nil, fmt.Errorf("describe configs: %w", err)
	}

	configs := make(map[string]string)
	for _, result := range results {
		for _, entry := range result.Config {
			if !entry.IsDefault {
				configs[entry.Name] = entry.Value
			}
		}
	}

	return &model.TopicDetail{
		Name:       name,
		Partitions: partitions,
		Configs:    configs,
	}, nil
}

func (c *Client) CreateTopic(ctx context.Context, req model.CreateTopicRequest) error {
	spec := kafka.TopicSpecification{
		Topic:             req.Name,
		NumPartitions:     int(req.Partitions),
		ReplicationFactor: int(req.ReplicationFactor),
		Config:            req.Configs,
	}

	results, err := c.admin.CreateTopics(ctx, []kafka.TopicSpecification{spec},
		kafka.SetAdminOperationTimeout(30*time.Second))
	if err != nil {
		return fmt.Errorf("create topic: %w", err)
	}

	for _, result := range results {
		if result.Error.Code() != kafka.ErrNoError {
			return fmt.Errorf("create topic %s: %s", result.Topic, result.Error.String())
		}
	}

	c.logger.Info("topic created", "name", req.Name, "partitions", req.Partitions)
	return nil
}

func (c *Client) UpdateTopicConfig(ctx context.Context, name string, configs map[string]string) error {
	var configEntries []kafka.ConfigEntry
	for k, v := range configs {
		configEntries = append(configEntries, kafka.ConfigEntry{
			Name:  k,
			Value: v,
		})
	}

	results, err := c.admin.IncrementalAlterConfigs(ctx, []kafka.ConfigResource{
		{
			Type:   kafka.ResourceTopic,
			Name:   name,
			Config: configEntries,
		},
	})
	if err != nil {
		return fmt.Errorf("alter configs: %w", err)
	}

	for _, result := range results {
		if result.Error.Code() != kafka.ErrNoError {
			return fmt.Errorf("alter config: %s", result.Error.String())
		}
	}

	c.logger.Info("topic config updated", "name", name)
	return nil
}

func (c *Client) ListConsumerGroups(ctx context.Context) ([]model.ConsumerGroup, error) {
	result, err := c.admin.ListConsumerGroups(ctx)
	if err != nil {
		return nil, fmt.Errorf("list consumer groups: %w", err)
	}

	groups := make([]model.ConsumerGroup, 0, len(result.Valid))
	for _, g := range result.Valid {
		groups = append(groups, model.ConsumerGroup{
			GroupID: g.GroupID,
			State:   g.State.String(),
		})
	}
	return groups, nil
}

func (c *Client) GetConsumerGroup(ctx context.Context, groupID string) (*model.ConsumerGroupDetail, error) {
	result, err := c.admin.DescribeConsumerGroups(ctx, []string{groupID})
	if err != nil {
		return nil, fmt.Errorf("describe consumer group: %w", err)
	}

	if len(result.ConsumerGroupDescriptions) == 0 {
		return nil, fmt.Errorf("consumer group %s not found", groupID)
	}

	g := result.ConsumerGroupDescriptions[0]
	if g.Error.Code() != kafka.ErrNoError {
		return nil, fmt.Errorf("describe group: %s", g.Error.String())
	}

	members := make([]model.Member, 0, len(g.Members))
	for _, m := range g.Members {
		assignments := make([]model.TopicPartition, 0)
		for _, tp := range m.Assignment.TopicPartitions {
			assignments = append(assignments, model.TopicPartition{
				Topic:     *tp.Topic,
				Partition: tp.Partition,
			})
		}
		members = append(members, model.Member{
			MemberID:   m.ConsumerID,
			ClientID:   m.ClientID,
			Host:       m.Host,
			Assignment: assignments,
		})
	}

	return &model.ConsumerGroupDetail{
		GroupID: g.GroupID,
		State:   g.State.String(),
		Coordinator: model.Broker{
			ID:   int32(g.Coordinator.ID),
			Host: g.Coordinator.Host,
			Port: int32(g.Coordinator.Port),
		},
		Members: members,
	}, nil
}
