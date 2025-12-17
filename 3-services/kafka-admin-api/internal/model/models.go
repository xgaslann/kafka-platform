package model

type Broker struct {
	ID   int32  `json:"id"`
	Host string `json:"host"`
	Port int32  `json:"port"`
}

type Topic struct {
	Name              string `json:"name"`
	PartitionCount    int    `json:"partition_count"`
	ReplicationFactor int    `json:"replication_factor"`
}

type TopicDetail struct {
	Name       string            `json:"name"`
	Partitions []Partition       `json:"partitions"`
	Configs    map[string]string `json:"configs"`
}

type Partition struct {
	ID       int32   `json:"id"`
	Leader   int32   `json:"leader"`
	Replicas []int32 `json:"replicas"`
	ISR      []int32 `json:"isr"`
}

type CreateTopicRequest struct {
	Name              string            `json:"name" validate:"required,min=1"`
	Partitions        int32             `json:"partitions" validate:"required,min=1"`
	ReplicationFactor int16             `json:"replication_factor" validate:"required,min=1,max=3"`
	Configs           map[string]string `json:"configs,omitempty"`
}

type UpdateTopicRequest struct {
	Configs map[string]string `json:"configs" validate:"required,min=1"`
}

type ConsumerGroup struct {
	GroupID      string `json:"group_id"`
	State        string `json:"state"`
	ProtocolType string `json:"protocol_type"`
}

type ConsumerGroupDetail struct {
	GroupID     string   `json:"group_id"`
	State       string   `json:"state"`
	Coordinator Broker   `json:"coordinator"`
	Members     []Member `json:"members"`
}

type Member struct {
	MemberID   string           `json:"member_id"`
	ClientID   string           `json:"client_id"`
	Host       string           `json:"host"`
	Assignment []TopicPartition `json:"assignment"`
}

type TopicPartition struct {
	Topic     string `json:"topic"`
	Partition int32  `json:"partition"`
	Offset    int64  `json:"offset"`
	Lag       int64  `json:"lag"`
}

// Consumer Message
type Message struct {
	Topic     string            `json:"topic"`
	Partition int32             `json:"partition"`
	Offset    int64             `json:"offset"`
	Key       string            `json:"key,omitempty"`
	Value     string            `json:"value"`
	Timestamp int64             `json:"timestamp"`
	Headers   map[string]string `json:"headers,omitempty"`
}

// Consume Request
type ConsumeRequest struct {
	GroupID     string `json:"group_id" validate:"required"`
	AutoOffset  string `json:"auto_offset"`  // earliest, latest
	MaxMessages int    `json:"max_messages"` // 0 = unlimited
}
