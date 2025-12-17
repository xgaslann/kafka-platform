#!/bin/bash
# ============================================================================
# KAFKA PLATFORM - API TEST SCRIPT
# ============================================================================
# Tüm API endpoint'lerini test eder ve çıktıları gösterir
# Usage: ./api-tests.sh
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_test() {
    echo -e "${YELLOW}► TEST $1: $2${NC}"
    echo -e "${CYAN}Command:${NC} $3"
    echo ""
}

wait_for_input() {
    echo ""
    echo -e "${CYAN}Press ENTER to continue...${NC}"
    read
}

# ============================================================================
# GET IPs
# ============================================================================
print_header "GETTING IP ADDRESSES"

cd ~/Projects/platform/kafka-platform/1-infrastructure/envs/dev
PLATFORM_IP=$(terraform output -json infrastructure_summary | jq -r '.platform.public_ip')
CONNECT_IP=$(terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip')
BROKER_IP=$(terraform output -json infrastructure_summary | jq -r '.brokers.public_ips[0]')
PLATFORM_PRIVATE_IP=$(terraform output -json infrastructure_summary | jq -r '.platform.private_ip')

echo "Platform IP:         $PLATFORM_IP"
echo "Platform Private IP: $PLATFORM_PRIVATE_IP"
echo "Connect IP:          $CONNECT_IP"
echo "Broker IP:           $BROKER_IP"

wait_for_input

print_header "KAFKA ADMIN REST API"

# ----------------------------------------------------------------------------
# TEST 1: Health check
# ----------------------------------------------------------------------------
print_test "1" "Health check" "GET /health"
curl -s "http://$PLATFORM_IP:2020/health" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 2: List all brokers
# ----------------------------------------------------------------------------
print_test "2" "List all brokers" "GET /brokers"
curl -s "http://$PLATFORM_IP:2020/brokers" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 3: List all topics
# ----------------------------------------------------------------------------
print_test "3" "List all topics" "GET /topics"
curl -s "http://$PLATFORM_IP:2020/topics" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 4: Describe topic
# ----------------------------------------------------------------------------
print_test "4" "Describe topic" "GET /topics/topic-1"
curl -s "http://$PLATFORM_IP:2020/topics/topic-1" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 5: Create topic
# ----------------------------------------------------------------------------
print_test "5" "Create topic" "POST /topics"
echo "Request body: {\"name\": \"topic-test\", \"partitions\": 3, \"replication_factor\": 3}"
echo ""
curl -s -X POST "http://$PLATFORM_IP:2020/topics" \
  -H "Content-Type: application/json" \
  -d '{"name": "topic-test", "partitions": 3, "replication_factor": 3}' | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 6: Alter topic configuration
# ----------------------------------------------------------------------------
print_test "6" "Alter topic configuration" "PUT /topics/topic-test"
echo "Request body: {\"configs\": {\"retention.ms\": \"86400000\"}}"
echo ""
curl -s -X PUT "http://$PLATFORM_IP:2020/topics/topic-test" \
  -H "Content-Type: application/json" \
  -d '{"configs": {"retention.ms": "86400000"}}' | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 7: Create consumer (background)
# ----------------------------------------------------------------------------
print_test "7" "Create consumer group" "kafka-console-consumer --group app-consumer-group"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER_IP "nohup kafka-console-consumer --bootstrap-server localhost:9092 --topic topic-1 --group app-consumer-group > /dev/null 2>&1 & sleep 2 && echo 'Consumer started with group: app-consumer-group'"
wait_for_input

# ----------------------------------------------------------------------------
# TEST 8: List all consumer groups
# ----------------------------------------------------------------------------
print_test "8" "List all consumer groups" "GET /consumer-groups"
curl -s "http://$PLATFORM_IP:2020/consumer-groups" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 9: Get consumer group details
# ----------------------------------------------------------------------------
print_test "9" "Get consumer group details" "GET /consumer-groups/app-consumer-group"
curl -s "http://$PLATFORM_IP:2020/consumer-groups/app-consumer-group" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 10: Consume messages (batch)
# ----------------------------------------------------------------------------
print_test "10" "Consume messages (batch)" "GET /topics/topic-1/consume?max=5"
curl -s "http://$PLATFORM_IP:2020/topics/topic-1/consume?group_id=batch-test-consumer&offset=earliest&max=5&timeout=10" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 11: Consume messages (SSE stream)
# ----------------------------------------------------------------------------
print_test "11" "Consume messages (SSE stream)" "GET /topics/topic-1/messages?max=3"
echo -e "${RED}SSE Stream output (3 messages):${NC}"
echo ""
curl -N -s "http://$PLATFORM_IP:2020/topics/topic-1/messages?group_id=sse-test-$$&offset=earliest&max=3"
echo ""
wait_for_input

# ============================================================================
# SECTION 5: KAFKA CONNECT REST API
# ============================================================================
print_header "SECTION 5: KAFKA CONNECT REST API"

# ----------------------------------------------------------------------------
# TEST 12: Get Connect cluster info
# ----------------------------------------------------------------------------
print_test "12" "Get Connect cluster info" "GET /"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 13: List connector plugins
# ----------------------------------------------------------------------------
print_test "13" "List connector plugins" "GET /connector-plugins"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connector-plugins" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 14: Validate connector configuration
# ----------------------------------------------------------------------------
print_test "14" "Validate connector configuration" "PUT /connector-plugins/HttpSourceConnector/config/validate"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s -X PUT localhost:8083/connector-plugins/HttpSourceConnector/config/validate -H 'Content-Type: application/json' -d '{\"name\": \"test-validation\", \"connector.class\": \"com.github.castorm.kafka.connect.http.HttpSourceConnector\", \"tasks.max\": \"1\", \"http.request.url\": \"http://$PLATFORM_PRIVATE_IP:2020/topics\", \"kafka.topic\": \"topic-1\"}'" | jq '{name: .name, error_count: .error_count}'
wait_for_input

# ----------------------------------------------------------------------------
# TEST 15: List connectors
# ----------------------------------------------------------------------------
print_test "15" "List connectors" "GET /connectors"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 16: Get connector details
# ----------------------------------------------------------------------------
print_test "16" "Get connector details" "GET /connectors/http-source-connector"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors/http-source-connector" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 17: Get connector status
# ----------------------------------------------------------------------------
print_test "17" "Get connector status" "GET /connectors/http-source-connector/status"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors/http-source-connector/status" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 18: List connector tasks
# ----------------------------------------------------------------------------
print_test "18" "List connector tasks" "GET /connectors/http-source-connector/tasks"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors/http-source-connector/tasks" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 19: Get task status
# ----------------------------------------------------------------------------
print_test "19" "Get task status" "GET /connectors/http-source-connector/tasks/0/status"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors/http-source-connector/tasks/0/status" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 20: Restart task
# ----------------------------------------------------------------------------
print_test "20" "Restart task" "POST /connectors/http-source-connector/tasks/0/restart"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s -X POST localhost:8083/connectors/http-source-connector/tasks/0/restart -w '%{http_code}'"
echo ""
echo "Task restarted (HTTP 204 = success)"
wait_for_input

# ----------------------------------------------------------------------------
# TEST 21: Update connector configuration
# ----------------------------------------------------------------------------
print_test "21" "Update connector configuration" "PUT /connectors/http-source-connector/config"
echo "Changing http.timer.interval.millis from 60000 to 30000"
echo ""
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s -X PUT localhost:8083/connectors/http-source-connector/config -H 'Content-Type: application/json' -d '{\"connector.class\": \"com.github.castorm.kafka.connect.http.HttpSourceConnector\", \"tasks.max\": \"1\", \"http.request.url\": \"http://$PLATFORM_PRIVATE_IP:2020/topics\", \"http.request.method\": \"GET\", \"kafka.topic\": \"topic-1\", \"http.timer.interval.millis\": \"30000\"}'" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 22: Delete connector
# ----------------------------------------------------------------------------
print_test "22" "Delete connector" "DELETE /connectors/http-source-connector"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s -X DELETE localhost:8083/connectors/http-source-connector -w '%{http_code}'"
echo ""
echo "Connector deleted (HTTP 204 = success)"
wait_for_input

# ----------------------------------------------------------------------------
# TEST 23: Create connector
# ----------------------------------------------------------------------------
print_test "23" "Create connector" "POST /connectors"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s -X POST localhost:8083/connectors -H 'Content-Type: application/json' -d '{\"name\": \"http-source-connector\", \"config\": {\"connector.class\": \"com.github.castorm.kafka.connect.http.HttpSourceConnector\", \"tasks.max\": \"1\", \"http.request.url\": \"http://$PLATFORM_PRIVATE_IP:2020/topics\", \"http.request.method\": \"GET\", \"kafka.topic\": \"topic-1\", \"http.timer.interval.millis\": \"60000\"}}'" | jq
wait_for_input

# ----------------------------------------------------------------------------
# TEST 24: Read messages from topic-1
# ----------------------------------------------------------------------------
print_test "24" "Read messages from topic-1" "kafka-console-consumer --topic topic-1"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER_IP "kafka-console-consumer --bootstrap-server localhost:9092 --topic topic-1 --from-beginning --max-messages 5 --timeout-ms 10000 2>/dev/null" || true
wait_for_input

# ----------------------------------------------------------------------------
# TEST 25: List consumer groups (CLI)
# ----------------------------------------------------------------------------
print_test "25" "List consumer groups (CLI)" "kafka-consumer-groups --list"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER_IP "kafka-consumer-groups --bootstrap-server localhost:9092 --list 2>/dev/null"
wait_for_input

# ----------------------------------------------------------------------------
# TEST 26: Describe consumer group (CLI)
# ----------------------------------------------------------------------------
print_test "26" "Describe consumer group (CLI)" "kafka-consumer-groups --describe --group app-consumer-group"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER_IP "kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group app-consumer-group 2>/dev/null" || echo "Consumer group may be empty"
wait_for_input

# ----------------------------------------------------------------------------
# TEST 27: Stop consumer
# ----------------------------------------------------------------------------
print_test "27" "Stop consumer" "pkill -f app-consumer-group"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER_IP "pkill -f 'app-consumer-group' 2>/dev/null && echo 'Consumer stopped' || echo 'No consumer to stop'"
wait_for_input

# ============================================================================
# SUMMARY
# ============================================================================
print_header "TEST SUMMARY"

echo "Section 4 - Kafka Admin REST API:"
echo "  GET    /health"
echo "  GET    /brokers"
echo "  GET    /topics"
echo "  GET    /topics/{name}"
echo "  POST   /topics"
echo "  PUT    /topics/{name}"
echo "  GET    /consumer-groups"
echo "  GET    /consumer-groups/{id}"
echo "  GET    /topics/{name}/consume (batch)"
echo "  GET    /topics/{name}/messages (SSE stream)"
echo ""
echo "Section 5 - Kafka Connect REST API:"
echo "  GET    /"
echo "  GET    /connector-plugins"
echo "  PUT    /connector-plugins/{name}/config/validate"
echo "  GET    /connectors"
echo "  POST   /connectors"
echo "  GET    /connectors/{name}"
echo "  GET    /connectors/{name}/status"
echo "  PUT    /connectors/{name}/config"
echo "  DELETE /connectors/{name}"
echo "  GET    /connectors/{name}/tasks"
echo "  GET    /connectors/{name}/tasks/{id}/status"
echo "  POST   /connectors/{name}/tasks/{id}/restart"
echo ""
echo "Bonus - Kafka CLI:"
echo " kafka-console-consumer"
echo " kafka-consumer-groups --list"
echo " kafka-consumer-groups --describe"
echo ""
echo -e "${GREEN}All 27 tests completed!${NC}"
echo ""
echo "Access URLs:"
echo "  Grafana:     http://$PLATFORM_IP:3000 (admin/admin)"
echo "  Prometheus:  http://$PLATFORM_IP:9090"
echo "  Kafka API:   http://$PLATFORM_IP:2020"
echo "  Connect:     http://$CONNECT_IP:8083 (internal only)"
