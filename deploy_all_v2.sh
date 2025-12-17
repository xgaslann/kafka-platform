#!/bin/bash
set -e

cd ~/Projects/platform/kafka-platform

# 1. Terraform
cd 1-infrastructure/envs/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# ► Get IPs
INFRA=$(terraform output -json infrastructure_summary)

PLATFORM_IP=$(echo $INFRA | jq -r '.platform.public_ip')
PLATFORM_PRIVATE_IP=$(echo $INFRA | jq -r '.platform.private_ip')
CONNECT_IP=$(echo $INFRA | jq -r '.kafka_connect.public_ip')

BROKER1_IP=$(echo $INFRA | jq -r '.brokers.public_ips[0]')
BROKER2_IP=$(echo $INFRA | jq -r '.brokers.public_ips[1]')
BROKER3_IP=$(echo $INFRA | jq -r '.brokers.public_ips[2]')
CONTROLLER1_IP=$(echo $INFRA | jq -r '.controllers.public_ips[0]')
CONTROLLER2_IP=$(echo $INFRA | jq -r '.controllers.public_ips[1]')
CONTROLLER3_IP=$(echo $INFRA | jq -r '.controllers.public_ips[2]')


# ► SSH Connection Test (wait 10s)
echo "► SSH Connection Test (wait 10s)..."
sleep 10
for ip in $CONTROLLER1_IP $CONTROLLER2_IP $CONTROLLER3_IP $BROKER1_IP $BROKER2_IP $BROKER3_IP $CONNECT_IP $PLATFORM_IP; do
    ssh -i ~/.ssh/kafka-platform-key -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$ip 'echo "SSH OK: $(hostname)"' || echo "FAILED: $ip"
done

cd ../../..

# 2. Inventory
cd 2-configuration
source ../.venv/bin/activate
./scripts/generate-inventory.sh

# ► Inventory Check
echo "► Inventory check:"
cat inventory/hosts.yml # | head -20

# 3. Ansible
ansible-playbook ./playbooks/pre-setup.yml
ansible-playbook ./playbooks/setup-hosts.yml

# ► Hosts Check
echo "► /etc/hosts check:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "cat /etc/hosts | grep -E 'controller|broker|connect|platform'"

ansible-playbook ~/.ansible/collections/ansible_collections/confluent/platform/playbooks/all.yml --limit kafka_controller,kafka_broker,kafka_connect -v

# ► Kafka Cluster Check
echo "► Service Status:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "systemctl is-active confluent-kcontroller"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "systemctl is-active confluent-server"

# ► Inter-node connectivity test
echo "► Inter-node connectivity test:"

echo "  Broker → Controller (9093):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "nc -zv controller-1 9093 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"

echo "  Broker → Broker (9092):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "nc -zv broker-2 9092 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER2_IP "nc -zv broker-3 9092 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"

echo "  Controller → Controller (9093):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "nc -zv controller-2 9093 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER2_IP "nc -zv controller-3 9093 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"

echo "  Connect → Broker (9092):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "nc -zv broker-1 9092 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"

echo "  Platform → Broker (9092):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$PLATFORM_IP "nc -zv broker-1 9092 2>&1 | grep -E 'succeeded|open'" || echo "  FAILED"

echo "► Quorum Status:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "sudo /opt/confluent/bin/kafka-metadata-quorum --bootstrap-controller localhost:9093 describe --status" || true
echo "► Controller Log (last 3):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "sudo journalctl -u confluent-kcontroller --no-pager -n 3"

ansible-playbook ./playbooks/node-exporter.yml

# ► Node Exporter Check
echo "► Node Exporter (9100):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "curl -s localhost:9100/metrics | head -2"

ansible-playbook ./playbooks/jmx-exporter.yml

# ► JMX Exporter Check
echo "► JMX Exporter Check:"
echo "  Broker (9999):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP "curl -s localhost:9999/metrics | grep kafka | head -2"
echo "  Controller (9998):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "curl -s localhost:9998/metrics | grep kafka | head -2"
echo "  Connect (7071):"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:7071/metrics | grep kafka | head -2" || echo "  (Connect not ready yet)"

ansible-playbook ./playbooks/monitoring-stack.yml

# ► Monitoring Check
echo "► Docker containers:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$PLATFORM_IP "docker ps --format 'table {{.Names}}\t{{.Status}}'"

ansible-playbook ./playbooks/kafka-admin-api.yml

# ► API Check
echo "► API Health:"
sleep 3
curl -s "http://$PLATFORM_IP:2020/health" | jq

ansible-playbook ./playbooks/kafka-connect.yml

# ► Connect Check
echo "► Connect container:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "docker ps --format '{{.Names}}: {{.Status}}'"
echo "► Connect plugins:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connector-plugins | jq '.[].class'"

# 4. Create Topics
curl -X POST "http://$PLATFORM_IP:2020/topics" -H "Content-Type: application/json" -d '{"name": "topic-1", "partitions": 3, "replication_factor": 3}'
curl -X POST "http://$PLATFORM_IP:2020/topics" -H "Content-Type: application/json" -d '{"name": "topic-2", "partitions": 3, "replication_factor": 3}'
curl -X POST "http://$PLATFORM_IP:2020/topics" -H "Content-Type: application/json" -d '{"name": "topic-3", "partitions": 3, "replication_factor": 3}'

# 5. Create HTTP Source Connector
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -X POST localhost:8083/connectors -H 'Content-Type: application/json' -d '{\"name\": \"http-source-connector\", \"config\": {\"connector.class\": \"com.github.castorm.kafka.connect.http.HttpSourceConnector\", \"tasks.max\": \"1\", \"http.request.url\": \"http://$PLATFORM_PRIVATE_IP:2020/topics\", \"http.request.method\": \"GET\", \"kafka.topic\": \"topic-1\", \"http.timer.interval.millis\": \"60000\"}}'"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors" | jq

echo ""
echo "=============================================="
echo "           VALIDATION CHECKS"
echo "=============================================="

echo ""
echo "► API Health Check:"
curl -s "http://$PLATFORM_IP:2020/health" | jq

echo ""
echo "► Broker List:"
curl -s "http://$PLATFORM_IP:2020/brokers" | jq

echo ""
echo "► Topic List:"
curl -s "http://$PLATFORM_IP:2020/topics" | jq

echo ""
echo "► Connector Status:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "curl -s localhost:8083/connectors/http-source-connector/status" | jq

echo ""
echo "► Prometheus Targets (UP):"
curl -s "http://$PLATFORM_IP:9090/api/v1/targets" | jq '.data.activeTargets[] | select(.health=="up") | {job: .labels.job, instance: .labels.instance}'

echo ""
echo "► Quorum & Leader:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONTROLLER1_IP "kafka-metadata-quorum --bootstrap-controller localhost:9093 describe --status"

echo ""
echo "► Under Replicated Partitions:"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$BROKER1_IP 'kafka-topics --bootstrap-server localhost:9092 --describe --under-replicated-partitions 2>&1 | grep -v "ERROR Reconfiguration"' || echo 'None (good)'
echo ""
echo "=============================================="
echo "              ACCESS INFO"
echo "=============================================="
echo "Platform:     $PLATFORM_IP"
echo "Connect:      $CONNECT_IP"
echo "Controller-1: $CONTROLLER1_IP"
echo "Controller-2: $CONTROLLER2_IP"
echo "Controller-3: $CONTROLLER3_IP"
echo "Broker-1:     $BROKER1_IP"
echo "Broker-2:     $BROKER2_IP"
echo "Broker-3:     $BROKER3_IP"
echo ""
echo "Kafka Admin API: http://$PLATFORM_IP:2020"
echo "Prometheus:      http://$PLATFORM_IP:9090"
echo "Grafana:         http://$PLATFORM_IP:3000 (admin/admin)"

# Before reaching Alertmanager, set alertmanager URL in Prometheus:
SG_ID=$(aws ec2 describe-instances --instance-ids i-0f0691be3866289ce --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
MY_IP=$(curl -s ifconfig.me)
echo "SG: $SG_ID, My IP: $MY_IP"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 9093 --cidr $MY_IP/32
# Revoke after use:
# aws ec2 revoke-security-group-ingress --group-id sg-0c7295a82240f6938 --protocol tcp --port 9093 --cidr 159.146.20.4/32
echo "Alertmanager:    http://$PLATFORM_IP:9093"
echo ""
echo "If IP changes: ./1-infrastructure/envs/dev/scripts/fix-ip.sh"
echo ""
echo "Deployment complete!"

aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=kafka-platform" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table

SG_ID=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=kafka-platform" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

echo "Security Group: $SG_ID"
echo ""
echo "Inbound Rules:"
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpProtocol,IpRanges[].CidrIp|[0],Description]' \
  --output table


  ssh -i ~/.ssh/kafka-platform-key ubuntu@$PLATFORM_IP "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$CONNECT_IP "docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh -i ~/.ssh/kafka-platform-key ubuntu@$PLATFORM_IP "docker logs prometheus --tail 30"
curl -s "http://$PLATFORM_IP:9090/api/v1/targets" | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.labels.instance)\t\(.health)"' | column -t
