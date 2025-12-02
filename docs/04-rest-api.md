# Section 4: REST API Service

> Kafka Admin API - Go + Fiber + confluent-kafka-go

## Overview

REST API service for Kafka cluster management using AdminClient. Built with Go and deployed as Docker container on platform node.

| Component | Technology              |
|-----------|-------------------------|
| Language | Go 1.25                 |
| Framework | Fiber v2                |
| Kafka Client | confluent-kafka-go v2   |
| Validation | go-playground/validator |
| Port | 2020                    |

## Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                      Platform Node                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            kafka-admin-api (Docker)                 │   │
│  │                    :2020                            │   │
│  └─────────────────────┬───────────────────────────────┘   │
│                        │                                    │
└────────────────────────┼────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │broker-1 │    │broker-2 │    │broker-3 │
    │  :9092  │    │  :9092  │    │  :9092  │
    └─────────┘    └─────────┘    └─────────┘
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| GET | /brokers | List all brokers |
| GET | /topics | List all topics |
| POST | /topics | Create topic |
| GET | /topics/{name} | Get topic details |
| PUT | /topics/{name} | Update topic config |
| GET | /consumer-groups | List consumer groups |
| GET | /consumer-groups/{id} | Get consumer group details |

## Deployment

### Ansible Playbook
```bash
cd 2-configuration
ansible-playbook -i inventory/hosts.yml playbooks/kafka-admin-api.yml
```

### Manual Docker Deployment
```bash
# On platform node
docker run -d \
  --name kafka-admin-api \
  --network host \
  -e KAFKA_BOOTSTRAP_SERVERS=10.0.101.166:9092,10.0.102.239:9092,10.0.103.53:9092 \
  kafka-admin-api:1.0.0
```

> **Important:** Platform node must have broker hostnames in `/etc/hosts` for DNS resolution.

## API Examples

### GET /brokers
```bash
curl http://63.180.202.85:2020/brokers
```

Response:
```json
[
  {"id":1,"host":"broker-1","port":9092},
  {"id":2,"host":"broker-2","port":9092},
  {"id":3,"host":"broker-3","port":9092}
]
```

### GET /topics
```bash
curl http://63.180.202.85:2020/topics
```

Response:
```json
[
  {"name":"topic-1","partition_count":3,"replication_factor":3},
  {"name":"topic-2","partition_count":3,"replication_factor":3},
  {"name":"test-topic","partition_count":3,"replication_factor":3}
]
```

### POST /topics
```bash
curl -X POST http://63.180.202.85:2020/topics \
  -H "Content-Type: application/json" \
  -d '{"name": "topic-1", "partitions": 3, "replication_factor": 3}'
```

Response:
```json
{"message":"topic created"}
```

### GET /topics/{name}
```bash
curl http://63.180.202.85:2020/topics/topic-1
```

Response:
```json
{
  "name": "topic-1",
  "partitions": [
    {"id":0,"leader":2,"replicas":[2,3,1],"isr":[2,3,1]},
    {"id":1,"leader":3,"replicas":[3,1,2],"isr":[3,1,2]},
    {"id":2,"leader":1,"replicas":[1,2,3],"isr":[1,2,3]}
  ],
  "configs": {
    "min.insync.replicas": "1",
    "retention.ms": "604800000",
    "segment.bytes": "1073741824"
  }
}
```

### PUT /topics/{name}
```bash
curl -X PUT http://63.180.202.85:2020/topics/topic-1 \
  -H "Content-Type: application/json" \
  -d '{"configs": {"retention.ms": "604800000"}}'
```

Response:
```json
{"message":"topic config updated"}
```

### GET /consumer-groups
```bash
curl http://63.180.202.85:2020/consumer-groups
```

Response:
```json
[]
```

### GET /consumer-groups/{id}
```bash
curl http://63.180.202.85:2020/consumer-groups/my-group
```

Response:
```json
{
  "group_id": "my-group",
  "state": "Stable",
  "coordinator": {"id":1,"host":"broker-1","port":9092},
  "members": ["..."]
}
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| PORT | Server port | 2020 |
| KAFKA_BOOTSTRAP_SERVERS | Broker addresses | required |
| KAFKA_SASL_USERNAME | SASL username | - |
| KAFKA_SASL_PASSWORD | SASL password | - |
| KAFKA_CA_LOCATION | CA cert path | - |

## Files
```
3-services/kafka-admin-api/
├── cmd/api/main.go
├── internal/
│   ├── config/config.go
│   ├── handler/
│   │   ├── handler.go
│   │   └── handler_test.go
│   ├── kafka/client.go
│   └── model/models.go
├── Dockerfile
├── Makefile
├── README.md
├── go.mod
└── go.sum

2-configuration/playbooks/
└── kafka-admin-api.yml
```

## Troubleshooting

### DNS Resolution Error

**Problem:** `Failed to resolve 'broker-1:9092'`

**Solution:** Add broker hostnames to `/etc/hosts` on platform node:
```bash
10.0.101.166 broker-1
10.0.102.239 broker-2
10.0.103.53 broker-3
```

### Timeout Error

**Problem:** `get metadata: Local: Timed out`

**Solution:**
1. Check broker connectivity: `nc -zv 10.0.101.166 9092`
2. Ensure container uses `--network host`
3. Verify broker hostnames in /etc/hosts

---

**Previous:** [Observability](./03-observability.md)  
**Next:** [Kafka Connect](./05-kafka-connect.md)