# Section 5: Kafka Connect

> Distributed Kafka Connect cluster with HTTP Source Connector

## Overview

Kafka Connect is deployed as a distributed cluster using Docker Compose. It polls the REST API (Section 4) and writes topic list data to `topic-1`.

| Component | Details |
|-----------|---------|
| Image | confluentinc/cp-kafka-connect:8.1.0 |
| Mode | Distributed |
| Workers | 1 |
| REST Port | 8083 |
| JMX Exporter Port | 7071 |

## Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                   Kafka Connect Node                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         kafka-connect (Docker Container)            │   │
│  │                                                     │   │
│  │  ┌─────────────────┐    ┌──────────────────────┐   │   │
│  │  │ HTTP Source     │    │ JMX Exporter         │   │   │
│  │  │ Connector       │    │ :7071                │   │   │
│  │  └────────┬────────┘    └──────────────────────┘   │   │
│  │           │                                         │   │
│  │           │ Poll every 30s                          │   │
│  │           ▼                                         │   │
│  │  http://platform:2020/topics                        │   │
│  │           │                                         │   │
│  │           │ Write to                                │   │
│  │           ▼                                         │   │
│  │       topic-1                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           :8083 REST API                    │
└─────────────────────────────────────────────────────────────┘
```

## Deployment

### Docker Compose
```yaml
services:
  kafka-connect:
    image: confluentinc/cp-kafka-connect:8.1.0
    hostname: kafka-connect-1
    container_name: kafka-connect
    network_mode: host
    environment:
      CONNECT_BOOTSTRAP_SERVERS: broker-1:9092,broker-2:9092,broker-3:9092
      CONNECT_REST_PORT: 8083
      CONNECT_REST_ADVERTISED_HOST_NAME: kafka-connect-1
      CONNECT_GROUP_ID: connect-cluster
      CONNECT_CONFIG_STORAGE_TOPIC: connect-cluster-configs
      CONNECT_OFFSET_STORAGE_TOPIC: connect-cluster-offsets
      CONNECT_STATUS_STORAGE_TOPIC: connect-cluster-status
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 3
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 3
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 3
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components
      EXTRA_ARGS: -javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=7071:/opt/jmx-exporter/kafka-connect.yml
    volumes:
      - connect-plugins:/usr/share/confluent-hub-components
      - /opt/kafka-connect/jmx-exporter:/opt/jmx-exporter:ro
    restart: unless-stopped

volumes:
  connect-plugins:
```

### HTTP Source Connector Installation
```bash
# Download plugin
cd /tmp
wget https://github.com/castorm/kafka-connect-http/releases/download/v0.8.11/kafka-connect-http-0.8.11-plugin.tar.gz
tar -xzf kafka-connect-http-0.8.11-plugin.tar.gz
docker cp kafka-connect-http kafka-connect:/usr/share/confluent-hub-components/
docker restart kafka-connect
```

### JMX Exporter Setup
```bash
mkdir -p /opt/kafka-connect/jmx-exporter
wget -O /opt/kafka-connect/jmx-exporter/jmx_prometheus_javaagent.jar \
  https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar
```

## Connector Configuration

### HTTP Source Connector
```bash
curl -X POST http://10.0.101.80:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "http-source-topics",
    "config": {
      "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
      "tasks.max": "1",
      "http.request.url": "http://10.0.101.207:2020/topics",
      "http.request.method": "GET",
      "http.timer.interval.millis": "30000",
      "kafka.topic": "topic-1"
    }
  }'
```

## REST API Operations

### Cluster Information
```bash
curl http://10.0.101.80:8083/
curl http://10.0.101.80:8083/connector-plugins
```

### Connector CRUD
```bash
curl http://10.0.101.80:8083/connectors                           # List
curl http://10.0.101.80:8083/connectors/http-source-topics        # Details
curl http://10.0.101.80:8083/connectors/http-source-topics/status # Status
curl -X DELETE http://10.0.101.80:8083/connectors/http-source-topics
```

### Task Operations
```bash
curl http://10.0.101.80:8083/connectors/http-source-topics/tasks
curl http://10.0.101.80:8083/connectors/http-source-topics/tasks/0/status
curl -X POST http://10.0.101.80:8083/connectors/http-source-topics/tasks/0/restart
```

## Troubleshooting

### JMX Port Conflict
**Symptom:** `Port already in use: 9997`
**Solution:** Use port 7071 for JMX Exporter, remove KAFKA_JMX_PORT env var.

### Container Restart Loop
**Check:** `docker logs kafka-connect --tail 50`
**Causes:** Cannot reach brokers, port conflict, missing plugins.

---
**Previous:** [REST API](./04-rest-api.md)
