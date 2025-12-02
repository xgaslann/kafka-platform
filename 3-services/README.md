# Kafka Admin API

REST API service for Kafka cluster management using AdminClient.

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

## Configuration

| Variable | Description | Required |
|----------|-------------|----------|
| PORT | Server port (default: 2020) | No |
| KAFKA_BOOTSTRAP_SERVERS | Kafka broker addresses | Yes |
| KAFKA_SASL_USERNAME | SASL username (for SASL_SSL) | No |
| KAFKA_SASL_PASSWORD | SASL password (for SASL_SSL) | No |
| KAFKA_CA_LOCATION | CA certificate path (for SASL_SSL) | No |

## Build & Run
```bash
# Build
make build

# Run locally
make dev

# Run tests
make test

# Build Docker image
make docker-build
```

## Docker Deployment
```bash
docker run -d \
  --name kafka-admin-api \
  --network host \
  -e KAFKA_BOOTSTRAP_SERVERS=broker-1:9092,broker-2:9092,broker-3:9092 \
  kafka-admin-api:1.0.0
```

> **Note:** Use `--network host` to allow DNS resolution of broker hostnames.

## API Examples

### List Brokers
```bash
curl http://localhost:2020/brokers
```
```json
[
  {"id":1,"host":"broker-1","port":9092},
  {"id":2,"host":"broker-2","port":9092},
  {"id":3,"host":"broker-3","port":9092}
]
```

### List Topics
```bash
curl http://localhost:2020/topics
```
```json
[
  {"name":"topic-1","partition_count":3,"replication_factor":3},
  {"name":"topic-2","partition_count":3,"replication_factor":3}
]
```

### Create Topic
```bash
curl -X POST http://localhost:2020/topics \
  -H "Content-Type: application/json" \
  -d '{"name": "my-topic", "partitions": 3, "replication_factor": 3}'
```
```json
{"message":"topic created"}
```

### Get Topic Details
```bash
curl http://localhost:2020/topics/topic-1
```
```json
{
  "name": "topic-1",
  "partitions": [
    {"id":0,"leader":2,"replicas":[2,3,1],"isr":[2,3,1]},
    {"id":1,"leader":3,"replicas":[3,1,2],"isr":[3,1,2]},
    {"id":2,"leader":1,"replicas":[1,2,3],"isr":[1,2,3]}
  ],
  "configs": {
    "retention.ms": "604800000",
    "segment.bytes": "1073741824"
  }
}
```

### Update Topic Config
```bash
curl -X PUT http://localhost:2020/topics/topic-1 \
  -H "Content-Type: application/json" \
  -d '{"configs": {"retention.ms": "604800000"}}'
```
```json
{"message":"topic config updated"}
```

### List Consumer Groups
```bash
curl http://localhost:2020/consumer-groups
```
```json
[
  {"group_id":"my-consumer-group","state":"Stable","protocol_type":"consumer"}
]
```

## Project Structure
```
kafka-admin-api/
├── cmd/api/main.go           # Application entry point
├── internal/
│   ├── config/config.go      # Configuration management
│   ├── handler/handler.go    # HTTP handlers
│   ├── kafka/client.go       # Kafka AdminClient wrapper
│   └── model/models.go       # Domain models
├── Dockerfile
├── Makefile
└── go.mod
```