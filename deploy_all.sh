#!/bin/bash
# ============================================================================
# KAFKA PLATFORM - FULL DEPLOYMENT SCRIPT
# ============================================================================
# This script deploys a complete Kafka platform including:
# - Infrastructure provisioning with Terraform (8 EC2 instances)
# - Kafka cluster deployment with cp-ansible (KRaft mode, 3 controllers, 3 brokers)
# - Observability stack (Prometheus, Grafana, Alertmanager)
# - Kafka Admin REST API (Go application)
# - Kafka Connect with HTTP Source Connector
#
# Prerequisites:
# - AWS credentials configured
# - SSH key at ~/.ssh/kafka-platform-key
# - Python virtual environment with Ansible at .venv/
# - cp-ansible collection installed
#
# Usage: ./deploy_all.sh
# ============================================================================

set -e  # Exit immediately on error

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ROOT=~/Projects/platform/kafka-platform
VENV_PATH=$PROJECT_ROOT/.venv
SSH_KEY=~/.ssh/kafka-platform-key
ANSIBLE_COLLECTION=~/.ansible/collections/ansible_collections/confluent/platform

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
print_header() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  $1${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}► Step $1: $2${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# ============================================================================
# MAIN DEPLOYMENT
# ============================================================================
print_header "KAFKA PLATFORM - FULL DEPLOYMENT"

# Activate Python virtual environment
# Required for Ansible and cp-ansible compatibility (Python 3.12.7, Ansible 10.6.0)
print_step "0" "Activating virtual environment..."
source $VENV_PATH/bin/activate
print_success "Virtual environment activated"

# ----------------------------------------------------------------------------
# STEP 1: TERRAFORM - INFRASTRUCTURE PROVISIONING
# ----------------------------------------------------------------------------
# Provisions 8 EC2 instances across 3 availability zones:
# - 3 Kafka Controllers (1 per AZ for quorum)
# - 3 Kafka Brokers (distributed across AZs)
# - 1 Kafka Connect node
# - 1 Platform node (observability stack)
print_step "1" "Provisioning infrastructure with Terraform..."
cd $PROJECT_ROOT/1-infrastructure/envs/dev

terraform init -input=false
terraform plan -out=tfplan
terraform apply tfplan

print_success "Infrastructure provisioned"

# ----------------------------------------------------------------------------
# STEP 2: GENERATE ANSIBLE INVENTORY
# ----------------------------------------------------------------------------
# Dynamically generates inventory from Terraform outputs
# - Extracts public/private IPs for all nodes
# - Sets up proper group variables for cp-ansible
# - Configures controller IDs with +9990 offset (KRaft requirement)
print_step "2" "Generating Ansible inventory from Terraform outputs..."
$PROJECT_ROOT/2-configuration/scripts/generate-inventory.sh
print_success "Inventory generated at 2-configuration/inventory/hosts.yml"

# ----------------------------------------------------------------------------
# STEP 3: WAIT FOR INSTANCES
# ----------------------------------------------------------------------------
# EC2 instances need time to fully initialize:
# - SSH daemon startup
# - Cloud-init completion
# - Network interface configuration
print_step "3" "Waiting 60 seconds for instances to initialize..."
sleep 60
print_success "Wait complete"

# ----------------------------------------------------------------------------
# STEP 4: TEST SSH CONNECTIVITY
# ----------------------------------------------------------------------------
# Verifies Ansible can reach all nodes before proceeding
# Prevents deployment failures due to connectivity issues
print_step "4" "Testing SSH connectivity to all nodes..."
cd $PROJECT_ROOT/2-configuration
ansible all -m ping
print_success "All nodes reachable"

# ----------------------------------------------------------------------------
# STEP 5: PRE-SETUP - NEEDRESTART CONFIGURATION
# ----------------------------------------------------------------------------
# Configures needrestart to automatic mode on all nodes
# Prevents interactive prompts during package installations
# Critical for unattended Ansible deployments
print_step "5" "Running pre-setup (needrestart configuration)..."
ansible-playbook ./playbooks/pre-setup.yml
print_success "Pre-setup complete"

# ----------------------------------------------------------------------------
# STEP 6: SETUP /etc/hosts WITH PRIVATE IPs
# ----------------------------------------------------------------------------
# Configures hostname resolution using private IPs
# Required for inter-node communication within VPC
# Public IPs would fail for internal Kafka replication
print_step "6" "Setting up /etc/hosts with private IPs..."
ansible-playbook ./playbooks/setup-hosts.yml
print_success "/etc/hosts configured on all nodes"

# ----------------------------------------------------------------------------
# STEP 7: DEPLOY KAFKA CLUSTER WITH CP-ANSIBLE
# ----------------------------------------------------------------------------
# Deploys Confluent Platform using cp-ansible:
# - KRaft mode (no ZooKeeper)
# - 3 dedicated controllers (process.roles=controller)
# - 3 brokers (process.roles=broker)
# - SASL_SSL with SCRAM-SHA-512 authentication (Method 2 - Plus Item)
# - Self-signed certificates for SSL
# - JMX enabled for metrics collection
#
# Note: --limit excludes platform node (not part of Kafka cluster)
print_step "7" "Deploying Kafka cluster with cp-ansible..."
ansible-playbook $ANSIBLE_COLLECTION/playbooks/all.yml \
    --limit kafka_controller,kafka_broker,kafka_connect -v
print_success "Kafka cluster deployed"

# ----------------------------------------------------------------------------
# STEP 8: CREATE KAFKA TOPICS
# ----------------------------------------------------------------------------
# Creates required topics as specified in the case study:
# - topic-1: Target for HTTP Source Connector
# - topic-2: Additional topic for testing
# Both with 3 partitions and replication factor 3
print_step "8" "Creating Kafka topics..."
cd $PROJECT_ROOT/1-infrastructure/envs/dev
BROKER_IP=$(terraform output -json broker_public_ips | jq -r '.[0]')

ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$BROKER_IP \
    "kafka-topics --bootstrap-server localhost:9092 --create --topic topic-1 --partitions 3 --replication-factor 3 --if-not-exists"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$BROKER_IP \
    "kafka-topics --bootstrap-server localhost:9092 --create --topic topic-2 --partitions 3 --replication-factor 3 --if-not-exists"
print_success "Topics created: topic-1, topic-2"

# ----------------------------------------------------------------------------
# STEP 9: DEPLOY NODE EXPORTER
# ----------------------------------------------------------------------------
# Installs node_exporter on all 8 nodes for system metrics:
# - CPU, Memory, Disk, Network metrics
# - Exposes metrics on port 9100
# - Required for infrastructure alerting
print_step "9" "Deploying Node Exporter on all nodes..."
cd $PROJECT_ROOT/2-configuration
ansible-playbook ./playbooks/node-exporter.yml
print_success "Node Exporter deployed"

# ----------------------------------------------------------------------------
# STEP 10: DEPLOY JMX EXPORTER
# ----------------------------------------------------------------------------
# Configures JMX Exporter for Kafka metrics:
# - Brokers: port 9999 (Kafka-specific metrics)
# - Controllers: port 9998 (KRaft metrics)
# - Exposes JMX MBeans as Prometheus metrics
print_step "10" "Deploying JMX Exporter on Kafka nodes..."
ansible-playbook ./playbooks/jmx-exporter.yml
print_success "JMX Exporter deployed"

# ----------------------------------------------------------------------------
# STEP 11: DEPLOY MONITORING STACK
# ----------------------------------------------------------------------------
# Deploys observability components on platform node:
# - Prometheus: Metrics collection and alerting rules
# - Grafana: Dashboards for Broker, Controller, Connect
# - Alertmanager: Alert routing and notification
# All running as Docker containers via docker-compose
print_step "11" "Deploying Monitoring Stack (Prometheus, Grafana, Alertmanager)..."
ansible-playbook ./playbooks/monitoring-stack.yml
print_success "Monitoring stack deployed"

# ----------------------------------------------------------------------------
# STEP 12: DEPLOY KAFKA ADMIN REST API
# ----------------------------------------------------------------------------
# Deploys custom REST API for Kafka administration:
# - Built with Go and Kafka AdminClient
# - Endpoints: /brokers, /topics, /consumer-groups
# - Runs as Docker container on port 2020
# - Used by HTTP Source Connector as data source
print_step "12" "Deploying Kafka Admin REST API..."
ansible-playbook ./playbooks/kafka-admin-api.yml
print_success "Kafka Admin REST API deployed on port 2020"

# ----------------------------------------------------------------------------
# STEP 13: DEPLOY KAFKA CONNECT
# ----------------------------------------------------------------------------
# Deploys Kafka Connect in distributed mode:
# - Single worker (case study requirement)
# - HTTP Source Connector plugin pre-installed
# - JMX enabled on port 7071 for monitoring
# - REST API on port 8083
print_step "13" "Deploying Kafka Connect..."
ansible-playbook ./playbooks/kafka-connect.yml
print_success "Kafka Connect deployed"

# ----------------------------------------------------------------------------
# STEP 14: WAIT FOR KAFKA CONNECT STARTUP
# ----------------------------------------------------------------------------
# Kafka Connect needs time to:
# - Start worker process
# - Create internal topics (offsets, configs, status)
# - Register with cluster
# - Load connector plugins
print_step "14" "Waiting 120 seconds for Kafka Connect to fully start..."
sleep 120
print_success "Wait complete"

# ----------------------------------------------------------------------------
# STEP 15: CREATE HTTP SOURCE CONNECTOR
# ----------------------------------------------------------------------------
# Creates connector that polls the Kafka Admin REST API:
# - Fetches topic list every 60 seconds
# - Writes results to topic-1
# - Demonstrates Connect + REST API integration
#
# Note: PassthroughRecordMapper removed (class not found in plugin version)
print_step "15" "Creating HTTP Source Connector..."
cd $PROJECT_ROOT/1-infrastructure/envs/dev
CONNECT_IP=$(terraform output -json connect_public_ips | jq -r '.[0]')
PLATFORM_PRIVATE_IP=$(terraform output -json platform_private_ips | jq -r '.[0]')

curl -X POST http://$CONNECT_IP:8083/connectors \
    -H "Content-Type: application/json" \
    -d '{
        "name": "http-source-connector",
        "config": {
            "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
            "tasks.max": "1",
            "http.request.url": "http://'$PLATFORM_PRIVATE_IP':2020/topics",
            "http.request.method": "GET",
            "http.timer.interval.millis": "60000",
            "kafka.topic": "topic-1"
        }
    }'

echo ""
print_success "HTTP Source Connector created"

# ----------------------------------------------------------------------------
# STEP 16: VERIFY CONNECTOR STATUS
# ----------------------------------------------------------------------------
print_step "16" "Verifying connector status..."
sleep 10
CONNECTOR_STATUS=$(curl -s http://$CONNECT_IP:8083/connectors/http-source-connector/status | jq -r '.connector.state')
TASK_STATUS=$(curl -s http://$CONNECT_IP:8083/connectors/http-source-connector/status | jq -r '.tasks[0].state')

if [ "$CONNECTOR_STATUS" == "RUNNING" ] && [ "$TASK_STATUS" == "RUNNING" ]; then
    print_success "Connector: $CONNECTOR_STATUS, Task: $TASK_STATUS"
else
    print_error "Connector: $CONNECTOR_STATUS, Task: $TASK_STATUS"
    echo "Check logs: ssh -i $SSH_KEY ubuntu@$CONNECT_IP 'docker logs kafka-connect'"
fi

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
print_header "DEPLOYMENT COMPLETE!"

# Get IPs for summary
PLATFORM_IP=$(terraform output -json platform_public_ips | jq -r '.[0]')

echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ ACCESS INFORMATION                                          │"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│ Grafana:       http://$PLATFORM_IP:3000  (admin/admin)      │"
echo "│ Prometheus:    http://$PLATFORM_IP:9090                     │"
echo "│ Alertmanager:  http://$PLATFORM_IP:9093                     │"
echo "│ Kafka Admin:   http://$PLATFORM_IP:2020                     │"
echo "│ Kafka Connect: http://$CONNECT_IP:8083                      │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ QUICK VERIFICATION COMMANDS                                 │"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│ Cluster health:                                             │"
echo "│   curl http://$PLATFORM_IP:2020/brokers | jq                │"
echo "│                                                             │"
echo "│ Topic list:                                                 │"
echo "│   curl http://$PLATFORM_IP:2020/topics | jq                 │"
echo "│                                                             │"
echo "│ Connector status:                                           │"
echo "│   curl http://$CONNECT_IP:8083/connectors/http-source-connector/status | jq │"
echo "│                                                             │"
echo "│ Prometheus targets:                                         │"
echo "│   curl http://$PLATFORM_IP:9090/api/v1/targets | jq '.data.activeTargets | length' │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""
print_success "All systems operational!"