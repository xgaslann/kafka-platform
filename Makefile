# =============================================================================
# KAFKA PLATFORM - MAKEFILE
# =============================================================================
# Production-Ready Kafka Infrastructure Management
# Author: Görkem Aslan
# =============================================================================

.PHONY: help infra-init infra-plan infra-apply infra-destroy infra-output \
        inventory ansible-ping kafka-deploy kafka-status \
        monitoring-deploy api-deploy connect-deploy \
        all clean ssh-broker ssh-controller ssh-platform ssh-connect \
        guide quickstart check-prereqs

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# VARIABLES
# =============================================================================
TF_DIR := 1-infrastructure/envs/dev
ANSIBLE_DIR := 2-configuration
API_DIR := 3-services/kafka-admin-api
PLATFORM_DIR := 4-platform
INVENTORY := $(ANSIBLE_DIR)/inventory/hosts.yml
SSH_KEY := ~/.ssh/kafka-platform-key
CP_ANSIBLE_PLAYBOOK := ~/.ansible/collections/ansible_collections/confluent/platform/playbooks/all.yml

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
BLUE := \033[0;34m
CYAN := \033[0;36m
BOLD := \033[1m
NC := \033[0m # No Color

# =============================================================================
# QUICK START GUIDE
# =============================================================================
guide: ## 📚 Show step-by-step deployment guide
	@echo ""
	@echo "$(BOLD)$(CYAN)╔══════════════════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BOLD)$(CYAN)║                    KAFKA PLATFORM - DEPLOYMENT GUIDE                        ║$(NC)"
	@echo "$(BOLD)$(CYAN)╚══════════════════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)PREREQUISITES:$(NC)"
	@echo "  Run: $(GREEN)make check-prereqs$(NC) to verify all tools are installed"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 1: INFRASTRUCTURE (Terraform) ~5 min$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)1.1$(NC) Initialize Terraform:"
	@echo "      $(GREEN)make infra-init$(NC)"
	@echo ""
	@echo "  $(CYAN)1.2$(NC) Review planned changes:"
	@echo "      $(GREEN)make infra-plan$(NC)"
	@echo ""
	@echo "  $(CYAN)1.3$(NC) Create infrastructure (8 EC2 instances):"
	@echo "      $(GREEN)make infra-apply$(NC)"
	@echo ""
	@echo "  $(CYAN)1.4$(NC) Generate Ansible inventory from Terraform output:"
	@echo "      $(GREEN)make inventory$(NC)"
	@echo ""
	@echo "  $(CYAN)1.5$(NC) Test SSH connectivity to all nodes:"
	@echo "      $(GREEN)make ansible-ping$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 2: KAFKA CLUSTER (cp-ansible) ~15-25 min$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)2.1$(NC) Activate Ansible virtual environment (if using):"
	@echo "      $(GREEN)source ~/kafka-ansible-venv/bin/activate$(NC)"
	@echo ""
	@echo "  $(CYAN)2.2$(NC) Deploy Kafka cluster (3 controllers + 3 brokers):"
	@echo "      $(GREEN)make kafka-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)2.3$(NC) Verify cluster status:"
	@echo "      $(GREEN)make kafka-status$(NC)"
	@echo ""
	@echo "  $(CYAN)2.4$(NC) Create required topics (topic-1, topic-2):"
	@echo "      $(GREEN)make kafka-create-topics$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 3: MONITORING STACK ~3 min$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)3.1$(NC) Deploy Node Exporter on all nodes:"
	@echo "      $(GREEN)make node-exporter-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)3.2$(NC) Deploy JMX Exporter on Kafka nodes:"
	@echo "      $(GREEN)make jmx-exporter-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)3.3$(NC) Deploy monitoring stack (Prometheus, Grafana, Alertmanager):"
	@echo "      $(GREEN)make monitoring-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)3.4$(NC) Verify Prometheus targets:"
	@echo "      $(GREEN)make prometheus-targets$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 4: REST API (Go) ~2 min$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)4.1$(NC) Deploy Kafka Admin API:"
	@echo "      $(GREEN)make api-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)4.2$(NC) Test API endpoints:"
	@echo "      $(GREEN)make api-test$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 5: KAFKA CONNECT ~3 min$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)5.1$(NC) Deploy Kafka Connect cluster:"
	@echo "      $(GREEN)make connect-deploy$(NC)"
	@echo ""
	@echo "  $(CYAN)5.2$(NC) Verify Connect is running:"
	@echo "      $(GREEN)make connect-status$(NC)"
	@echo ""
	@echo "  $(CYAN)5.3$(NC) Create HTTP Source Connector:"
	@echo "      $(GREEN)make connect-create-http-source$(NC)"
	@echo ""
	@echo "  $(CYAN)5.4$(NC) Check connector status:"
	@echo "      $(GREEN)make connect-connectors-status$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(YELLOW)STEP 6: VERIFICATION$(NC)"
	@echo "$(BOLD)$(YELLOW)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "  $(CYAN)6.1$(NC) Check all service URLs:"
	@echo "      $(GREEN)make urls$(NC)"
	@echo ""
	@echo "  $(CYAN)6.2$(NC) Check overall system status:"
	@echo "      $(GREEN)make status$(NC)"
	@echo ""
	@echo "  $(CYAN)6.3$(NC) Consume messages from topic-1 (verify Connect is working):"
	@echo "      $(GREEN)make kafka-consume TOPIC=topic-1$(NC)"
	@echo ""
	@echo "$(BOLD)$(GREEN)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BOLD)$(GREEN)✅ DEPLOYMENT COMPLETE! Total time: ~30-40 minutes$(NC)"
	@echo "$(BOLD)$(GREEN)═══════════════════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)QUICK COMMANDS:$(NC)"
	@echo "  $(GREEN)make all$(NC)          - Run steps 1.1-1.5 automatically"
	@echo "  $(GREEN)make deploy-all$(NC)   - Run steps 2-5 automatically (after 'make all')"
	@echo "  $(GREEN)make status$(NC)       - Check all services"
	@echo "  $(GREEN)make urls$(NC)         - Show service URLs"
	@echo "  $(GREEN)make clean$(NC)        - Stop all services (keep infra)"
	@echo "  $(GREEN)make infra-destroy$(NC) - Destroy all AWS resources"
	@echo ""
	@echo "$(BOLD)$(YELLOW)SSH ACCESS:$(NC)"
	@echo "  $(GREEN)make ssh-broker$(NC)     - SSH to broker-1 (N=2 for broker-2)"
	@echo "  $(GREEN)make ssh-controller$(NC) - SSH to controller-1"
	@echo "  $(GREEN)make ssh-platform$(NC)   - SSH to platform node"
	@echo "  $(GREEN)make ssh-connect$(NC)    - SSH to kafka-connect node"
	@echo ""

quickstart: guide ## 🚀 Alias for 'guide'

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
check-prereqs: ## 🔍 Check if all required tools are installed
	@echo ""
	@echo "$(BOLD)$(CYAN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BOLD)$(CYAN)║              PREREQUISITES CHECK                             ║$(NC)"
	@echo "$(BOLD)$(CYAN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking required tools...$(NC)"
	@echo ""
	@printf "  %-20s" "Terraform:"
	@if command -v terraform >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)$(NC)"; \
	else \
		echo "$(RED)✗ Not installed$(NC)"; \
	fi
	@printf "  %-20s" "AWS CLI:"
	@if command -v aws >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(aws --version 2>&1 | cut -d' ' -f1)$(NC)"; \
	else \
		echo "$(RED)✗ Not installed$(NC)"; \
	fi
	@printf "  %-20s" "Ansible:"
	@if command -v ansible >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(ansible --version | head -1)$(NC)"; \
	else \
		echo "$(RED)✗ Not installed$(NC)"; \
	fi
	@printf "  %-20s" "Go:"
	@if command -v go >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(go version | cut -d' ' -f3)$(NC)"; \
	else \
		echo "$(YELLOW)⚠ Not installed (optional for local dev)$(NC)"; \
	fi
	@printf "  %-20s" "Docker:"
	@if command -v docker >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(docker --version | cut -d' ' -f3 | tr -d ',')$(NC)"; \
	else \
		echo "$(RED)✗ Not installed$(NC)"; \
	fi
	@printf "  %-20s" "jq:"
	@if command -v jq >/dev/null 2>&1; then \
		echo "$(GREEN)✓ $$(jq --version)$(NC)"; \
	else \
		echo "$(RED)✗ Not installed$(NC)"; \
	fi
	@printf "  %-20s" "SSH Key:"
	@if [ -f $(SSH_KEY) ]; then \
		echo "$(GREEN)✓ $(SSH_KEY) exists$(NC)"; \
	else \
		echo "$(RED)✗ $(SSH_KEY) not found$(NC)"; \
	fi
	@printf "  %-20s" "cp-ansible:"
	@if [ -d ~/.ansible/collections/ansible_collections/confluent/platform ]; then \
		echo "$(GREEN)✓ Installed$(NC)"; \
	else \
		echo "$(RED)✗ Not installed (run: ansible-galaxy collection install confluent.platform:7.9.0)$(NC)"; \
	fi
	@printf "  %-20s" "AWS Credentials:"
	@if aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Configured$(NC)"; \
	else \
		echo "$(RED)✗ Not configured (run: aws configure)$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)Checking project structure...$(NC)"
	@echo ""
	@printf "  %-20s" "Terraform dir:"
	@if [ -d $(TF_DIR) ]; then \
		echo "$(GREEN)✓ $(TF_DIR)$(NC)"; \
	else \
		echo "$(RED)✗ $(TF_DIR) not found$(NC)"; \
	fi
	@printf "  %-20s" "Ansible dir:"
	@if [ -d $(ANSIBLE_DIR) ]; then \
		echo "$(GREEN)✓ $(ANSIBLE_DIR)$(NC)"; \
	else \
		echo "$(RED)✗ $(ANSIBLE_DIR) not found$(NC)"; \
	fi
	@printf "  %-20s" "API dir:"
	@if [ -d $(API_DIR) ]; then \
		echo "$(GREEN)✓ $(API_DIR)$(NC)"; \
	else \
		echo "$(RED)✗ $(API_DIR) not found$(NC)"; \
	fi
	@printf "  %-20s" "Platform dir:"
	@if [ -d $(PLATFORM_DIR) ]; then \
		echo "$(GREEN)✓ $(PLATFORM_DIR)$(NC)"; \
	else \
		echo "$(RED)✗ $(PLATFORM_DIR) not found$(NC)"; \
	fi
	@echo ""
	@echo "$(GREEN)Prerequisites check complete!$(NC)"
	@echo ""

# =============================================================================
# HELP
# =============================================================================
help: ## Show this help
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║           KAFKA PLATFORM - COMMAND REFERENCE                 ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BOLD)$(CYAN)Quick Start:$(NC)"
	@echo "  $(GREEN)make guide$(NC)           📚 Show step-by-step deployment guide"
	@echo "  $(GREEN)make check-prereqs$(NC)   🔍 Check if all tools are installed"
	@echo ""
	@echo "$(YELLOW)Infrastructure (Terraform):$(NC)"
	@grep -E '^infra-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Inventory Management:$(NC)"
	@grep -E '^inventory[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Ansible Operations:$(NC)"
	@grep -E '^ansible-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Kafka Cluster:$(NC)"
	@grep -E '^kafka-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Monitoring Stack:$(NC)"
	@grep -E '^(monitoring|node-exporter|jmx-exporter|prometheus)[a-zA-Z_-]*:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Kafka Admin API:$(NC)"
	@grep -E '^api-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Kafka Connect:$(NC)"
	@grep -E '^connect-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)SSH Access:$(NC)"
	@grep -E '^ssh-[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Workflows:$(NC)"
	@grep -E '^(all|deploy-all|status|clean|validate):.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@grep -E '^(fix-hosts|setup-hosts|update-sg|urls|logs):.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# INFRASTRUCTURE (TERRAFORM)
# =============================================================================
infra-init: ## Initialize Terraform
	@echo "$(GREEN)► Initializing Terraform...$(NC)"
	cd $(TF_DIR) && terraform init

infra-plan: ## Plan infrastructure changes
	@echo "$(GREEN)► Planning infrastructure...$(NC)"
	cd $(TF_DIR) && terraform plan

infra-apply: ## Apply infrastructure (create/update)
	@echo "$(GREEN)► Applying infrastructure...$(NC)"
	cd $(TF_DIR) && terraform apply

infra-apply-auto: ## Apply infrastructure without confirmation
	@echo "$(GREEN)► Applying infrastructure (auto-approve)...$(NC)"
	cd $(TF_DIR) && terraform apply -auto-approve

infra-destroy: ## Destroy all infrastructure
	@echo "$(RED)► Destroying infrastructure...$(NC)"
	cd $(TF_DIR) && terraform destroy

infra-destroy-auto: ## Destroy all infrastructure without confirmation
	@echo "$(RED)► Destroying infrastructure (auto-approve)...$(NC)"
	cd $(TF_DIR) && terraform destroy -auto-approve

infra-output: ## Show Terraform outputs
	@echo "$(GREEN)► Terraform Outputs:$(NC)"
	cd $(TF_DIR) && terraform output

infra-refresh: ## Refresh Terraform state
	@echo "$(GREEN)► Refreshing Terraform state...$(NC)"
	cd $(TF_DIR) && terraform refresh

infra-state: ## Show Terraform state list
	@echo "$(GREEN)► Terraform State:$(NC)"
	cd $(TF_DIR) && terraform state list

infra-cost: ## Show estimated monthly cost
	@echo "$(GREEN)► Estimated Monthly Cost:$(NC)"
	cd $(TF_DIR) && terraform output monthly_cost_estimate

infra-validate: ## Validate Terraform configuration
	@echo "$(GREEN)► Validating Terraform...$(NC)"
	cd $(TF_DIR) && terraform validate

infra-fmt: ## Format Terraform files
	@echo "$(GREEN)► Formatting Terraform files...$(NC)"
	cd $(TF_DIR) && terraform fmt -recursive

# =============================================================================
# INVENTORY MANAGEMENT
# =============================================================================
inventory: ## Generate Ansible inventory from Terraform output
	@echo "$(GREEN)► Generating Ansible inventory...$(NC)"
	cd $(TF_DIR) && terraform output -raw ansible_inventory > ../../../$(INVENTORY)
	@echo "$(GREEN)✓ Inventory saved to $(INVENTORY)$(NC)"

inventory-show: ## Show current inventory
	@echo "$(GREEN)► Current Inventory:$(NC)"
	@cat $(INVENTORY)

inventory-json: ## Show inventory in JSON format
	@echo "$(GREEN)► Inventory (JSON):$(NC)"
	cd $(TF_DIR) && terraform output -json ansible_inventory | jq

inventory-ips: ## Show all instance IPs
	@echo "$(GREEN)► Instance IPs:$(NC)"
	@cd $(TF_DIR) && terraform output -json infrastructure_summary | jq '{brokers: .brokers.public_ips, controllers: .controllers.public_ips, kafka_connect: .kafka_connect.public_ip, platform: .platform.public_ip}'

# =============================================================================
# ANSIBLE OPERATIONS
# =============================================================================
ansible-ping: ## Test connectivity to all hosts
	@echo "$(GREEN)► Pinging all hosts...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -m ping

ansible-ping-brokers: ## Test connectivity to brokers only
	@echo "$(GREEN)► Pinging brokers...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_broker -m ping

ansible-ping-controllers: ## Test connectivity to controllers only
	@echo "$(GREEN)► Pinging controllers...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_controller -m ping

ansible-facts: ## Gather facts from all hosts
	@echo "$(GREEN)► Gathering facts...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -m setup

ansible-uptime: ## Check uptime on all hosts
	@echo "$(GREEN)► Checking uptime...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -a "uptime"

ansible-memory: ## Check memory usage on all hosts
	@echo "$(GREEN)► Checking memory...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -a "free -h"

ansible-disk: ## Check disk usage on all hosts
	@echo "$(GREEN)► Checking disk...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -a "df -h"

ansible-java: ## Check Java version on Kafka nodes
	@echo "$(GREEN)► Checking Java version...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_broker:kafka_controller -a "java -version"

ansible-reboot: ## Reboot all hosts (use with caution!)
	@echo "$(RED)► Rebooting all hosts...$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -a "reboot" --become

# =============================================================================
# KAFKA CLUSTER DEPLOYMENT
# =============================================================================
kafka-deploy: ## Deploy Kafka cluster with cp-ansible
	@echo "$(GREEN)► Deploying Kafka cluster...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.yml $(CP_ANSIBLE_PLAYBOOK)

kafka-deploy-check: ## Dry-run Kafka deployment (check mode)
	@echo "$(GREEN)► Checking Kafka deployment (dry-run)...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.yml $(CP_ANSIBLE_PLAYBOOK) --check

kafka-deploy-verbose: ## Deploy Kafka cluster with verbose output
	@echo "$(GREEN)► Deploying Kafka cluster (verbose)...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.yml $(CP_ANSIBLE_PLAYBOOK) -vvv

kafka-status: ## Check Kafka cluster status
	@echo "$(GREEN)► Broker status:$(NC)"
	-cd $(ANSIBLE_DIR) && ansible kafka_broker -a "systemctl status confluent-server --no-pager" --become
	@echo ""
	@echo "$(GREEN)► Controller status:$(NC)"
	-cd $(ANSIBLE_DIR) && ansible kafka_controller -a "systemctl status confluent-kcontroller --no-pager" --become

kafka-start: ## Start Kafka services
	@echo "$(GREEN)► Starting Kafka services...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_controller -a "systemctl start confluent-kcontroller" --become
	cd $(ANSIBLE_DIR) && ansible kafka_broker -a "systemctl start confluent-server" --become

kafka-stop: ## Stop Kafka services
	@echo "$(YELLOW)► Stopping Kafka services...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_broker -a "systemctl stop confluent-server" --become
	cd $(ANSIBLE_DIR) && ansible kafka_controller -a "systemctl stop confluent-kcontroller" --become

kafka-restart: ## Restart Kafka services
	@echo "$(YELLOW)► Restarting Kafka services...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_broker -a "systemctl restart confluent-server" --become
	cd $(ANSIBLE_DIR) && ansible kafka_controller -a "systemctl restart confluent-kcontroller" --become

kafka-logs-broker: ## Show broker logs (last 50 lines)
	@echo "$(GREEN)► Broker logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_broker -a "tail -50 /var/log/kafka/server.log" --become

kafka-logs-controller: ## Show controller logs (last 50 lines)
	@echo "$(GREEN)► Controller logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_controller -a "tail -50 /var/log/controller/controller.log" --become

kafka-logs-broker-follow: ## Follow broker logs (broker-1)
	@echo "$(GREEN)► Following broker-1 logs...$(NC)"
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.brokers.public_ips[0]'); \
	ssh -i $(SSH_KEY) ubuntu@$$IP "sudo tail -f /var/log/kafka/server.log"

kafka-topics: ## List Kafka topics
	@echo "$(GREEN)► Listing topics...$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-topics --bootstrap-server localhost:9092 --list" --become

kafka-topics-describe: ## Describe all topics in detail
	@echo "$(GREEN)► Describing topics...$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-topics --bootstrap-server localhost:9092 --describe" --become

kafka-create-topics: ## Create required topics (topic-1, topic-2)
	@echo "$(GREEN)► Creating topics...$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-topics --bootstrap-server localhost:9092 --create --topic topic-1 --partitions 3 --replication-factor 3 --if-not-exists" --become
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-topics --bootstrap-server localhost:9092 --create --topic topic-2 --partitions 3 --replication-factor 3 --if-not-exists" --become

kafka-delete-topic: ## Delete a topic (usage: make kafka-delete-topic TOPIC=my-topic)
	@echo "$(RED)► Deleting topic: $(TOPIC)$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-topics --bootstrap-server localhost:9092 --delete --topic $(TOPIC)" --become

kafka-consumer-groups: ## List all consumer groups
	@echo "$(GREEN)► Listing consumer groups...$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-consumer-groups --bootstrap-server localhost:9092 --list" --become

kafka-consumer-group-describe: ## Describe consumer group (usage: make kafka-consumer-group-describe GROUP=my-group)
	@echo "$(GREEN)► Describing consumer group: $(GROUP)$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-consumer-groups --bootstrap-server localhost:9092 --group $(GROUP) --describe" --become

kafka-produce: ## Produce test message (usage: make kafka-produce TOPIC=topic-1 MSG="hello")
	@echo "$(GREEN)► Producing message to $(TOPIC)...$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"echo '$(MSG)' | kafka-console-producer --bootstrap-server localhost:9092 --topic $(TOPIC)" --become

kafka-consume: ## Consume messages from topic (usage: make kafka-consume TOPIC=topic-1)
	@echo "$(GREEN)► Consuming from $(TOPIC) (max 10 messages)...$(NC)"
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.brokers.public_ips[0]'); \
	ssh -i $(SSH_KEY) ubuntu@$$IP "kafka-console-consumer --bootstrap-server localhost:9092 --topic $(TOPIC) --from-beginning --max-messages 10"

kafka-cluster-id: ## Show Kafka cluster ID
	@echo "$(GREEN)► Cluster ID:$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-metadata --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log --cluster-id" --become

kafka-brokers-info: ## Show broker API versions
	@echo "$(GREEN)► Broker API versions:$(NC)"
	cd $(ANSIBLE_DIR) && ansible broker-1 -a \
		"kafka-broker-api-versions --bootstrap-server localhost:9092" --become

# =============================================================================
# MONITORING STACK
# =============================================================================
monitoring-deploy: ## Deploy monitoring stack (Prometheus, Grafana, Alertmanager)
	@echo "$(GREEN)► Deploying monitoring stack...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/monitoring-stack.yml

monitoring-status: ## Check monitoring stack container status
	@echo "$(GREEN)► Monitoring containers:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" --become

monitoring-start: ## Start monitoring stack
	@echo "$(GREEN)► Starting monitoring stack...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "cd /opt/monitoring && docker compose up -d" --become

monitoring-stop: ## Stop monitoring stack
	@echo "$(YELLOW)► Stopping monitoring stack...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "cd /opt/monitoring && docker compose down" --become

monitoring-restart: ## Restart monitoring stack
	@echo "$(YELLOW)► Restarting monitoring stack...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "cd /opt/monitoring && docker compose restart" --become

monitoring-logs: ## Show monitoring stack logs
	@echo "$(GREEN)► Monitoring logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "cd /opt/monitoring && docker compose logs --tail 50" --become

monitoring-logs-prometheus: ## Show Prometheus logs
	@echo "$(GREEN)► Prometheus logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker logs prometheus --tail 50" --become

monitoring-logs-grafana: ## Show Grafana logs
	@echo "$(GREEN)► Grafana logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker logs grafana --tail 50" --become

node-exporter-deploy: ## Deploy node_exporter on all nodes
	@echo "$(GREEN)► Deploying node_exporter...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/node-exporter.yml

node-exporter-status: ## Check node_exporter status on all nodes
	@echo "$(GREEN)► node_exporter status:$(NC)"
	cd $(ANSIBLE_DIR) && ansible all -a "systemctl status node_exporter --no-pager" --become

jmx-exporter-deploy: ## Deploy JMX exporter on Kafka nodes
	@echo "$(GREEN)► Deploying JMX exporter...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/jmx-exporter.yml

prometheus-targets: ## Check Prometheus targets health
	@echo "$(GREEN)► Prometheus targets:$(NC)"
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

prometheus-alerts: ## Check active Prometheus alerts
	@echo "$(GREEN)► Active alerts:$(NC)"
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:9090/api/v1/alerts | jq '.data.alerts'

# =============================================================================
# KAFKA ADMIN API
# =============================================================================
api-build: ## Build API binary locally
	@echo "$(GREEN)► Building API...$(NC)"
	cd $(API_DIR) && go build -o bin/kafka-admin-api ./cmd/api

api-test-local: ## Run API unit tests
	@echo "$(GREEN)► Running tests...$(NC)"
	cd $(API_DIR) && go test -v ./...

api-test-coverage: ## Run API tests with coverage report
	@echo "$(GREEN)► Running tests with coverage...$(NC)"
	cd $(API_DIR) && go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)✓ Coverage report: $(API_DIR)/coverage.html$(NC)"

api-lint: ## Lint API code with golangci-lint
	@echo "$(GREEN)► Linting...$(NC)"
	cd $(API_DIR) && golangci-lint run

api-fmt: ## Format API Go code
	@echo "$(GREEN)► Formatting...$(NC)"
	cd $(API_DIR) && go fmt ./...

api-docker-build: ## Build API Docker image locally
	@echo "$(GREEN)► Building Docker image...$(NC)"
	cd $(API_DIR) && docker build -t kafka-admin-api:1.0.0 .

api-deploy: ## Deploy Kafka Admin API to platform node
	@echo "$(GREEN)► Deploying Kafka Admin API...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/kafka-admin-api.yml

api-status: ## Check API container status
	@echo "$(GREEN)► API container status:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker ps -f name=kafka-admin-api --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" --become

api-start: ## Start API container
	@echo "$(GREEN)► Starting API...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker start kafka-admin-api" --become

api-stop: ## Stop API container
	@echo "$(YELLOW)► Stopping API...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker stop kafka-admin-api" --become

api-restart: ## Restart API container
	@echo "$(YELLOW)► Restarting API...$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker restart kafka-admin-api" --become

api-logs: ## Show API container logs
	@echo "$(GREEN)► API logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible platform -a "docker logs kafka-admin-api --tail 100" --become

api-logs-follow: ## Follow API logs in real-time
	@echo "$(GREEN)► Following API logs (Ctrl+C to stop)...$(NC)"
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	ssh -i $(SSH_KEY) ubuntu@$$IP "docker logs -f kafka-admin-api"

api-test: ## Test all API endpoints
	@echo "$(GREEN)► Testing API endpoints...$(NC)"
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	echo "\n$(BLUE)GET /health$(NC)"; \
	curl -s http://$$PLATFORM_IP:2020/health | jq; \
	echo "\n$(BLUE)GET /brokers$(NC)"; \
	curl -s http://$$PLATFORM_IP:2020/brokers | jq; \
	echo "\n$(BLUE)GET /topics$(NC)"; \
	curl -s http://$$PLATFORM_IP:2020/topics | jq; \
	echo "\n$(BLUE)GET /consumer-groups$(NC)"; \
	curl -s http://$$PLATFORM_IP:2020/consumer-groups | jq

api-test-health: ## Test API health endpoint
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:2020/health | jq

api-test-brokers: ## Test API brokers endpoint
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:2020/brokers | jq

api-test-topics: ## Test API topics endpoint
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:2020/topics | jq

api-test-topic: ## Get specific topic details (usage: make api-test-topic TOPIC=topic-1)
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s http://$$PLATFORM_IP:2020/topics/$(TOPIC) | jq

api-create-topic: ## Create topic via API (usage: make api-create-topic NAME=my-topic PARTITIONS=3 RF=3)
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	curl -s -X POST http://$$PLATFORM_IP:2020/topics \
		-H "Content-Type: application/json" \
		-d '{"name": "$(NAME)", "partitions": $(PARTITIONS), "replication_factor": $(RF)}' | jq

# =============================================================================
# KAFKA CONNECT
# =============================================================================
connect-deploy: ## Deploy Kafka Connect cluster
	@echo "$(GREEN)► Deploying Kafka Connect...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/kafka-connect.yml

connect-status: ## Check Kafka Connect cluster info
	@echo "$(GREEN)► Kafka Connect cluster info:$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/ | jq

connect-start: ## Start Kafka Connect container
	@echo "$(GREEN)► Starting Kafka Connect...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_connect -a "cd /opt/kafka-connect && docker compose up -d" --become

connect-stop: ## Stop Kafka Connect container
	@echo "$(YELLOW)► Stopping Kafka Connect...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_connect -a "cd /opt/kafka-connect && docker compose down" --become

connect-restart: ## Restart Kafka Connect container
	@echo "$(YELLOW)► Restarting Kafka Connect...$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_connect -a "cd /opt/kafka-connect && docker compose restart" --become

connect-plugins: ## List installed Kafka Connect plugins
	@echo "$(GREEN)► Connector plugins:$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/connector-plugins | jq

connect-connectors: ## List all connectors
	@echo "$(GREEN)► Connectors:$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/connectors | jq

connect-connectors-status: ## Show status of all connectors
	@echo "$(GREEN)► Connector statuses:$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	for conn in $$(curl -s http://$$CONNECT_IP:8083/connectors | jq -r '.[]'); do \
		echo "\n$(BLUE)$$conn:$(NC)"; \
		curl -s http://$$CONNECT_IP:8083/connectors/$$conn/status | jq; \
	done

connect-connector-status: ## Get connector status (usage: make connect-connector-status CONNECTOR=my-connector)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/status | jq

connect-connector-config: ## Get connector config (usage: make connect-connector-config CONNECTOR=my-connector)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/config | jq

connect-connector-delete: ## Delete connector (usage: make connect-connector-delete CONNECTOR=my-connector)
	@echo "$(RED)► Deleting connector: $(CONNECTOR)$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X DELETE http://$$CONNECT_IP:8083/connectors/$(CONNECTOR) | jq

connect-connector-restart: ## Restart connector (usage: make connect-connector-restart CONNECTOR=my-connector)
	@echo "$(YELLOW)► Restarting connector: $(CONNECTOR)$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X POST http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/restart | jq

connect-connector-pause: ## Pause connector (usage: make connect-connector-pause CONNECTOR=my-connector)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X PUT http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/pause

connect-connector-resume: ## Resume connector (usage: make connect-connector-resume CONNECTOR=my-connector)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X PUT http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/resume

connect-tasks: ## List connector tasks (usage: make connect-tasks CONNECTOR=my-connector)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/tasks | jq

connect-task-restart: ## Restart specific task (usage: make connect-task-restart CONNECTOR=my-connector TASK=0)
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X POST http://$$CONNECT_IP:8083/connectors/$(CONNECTOR)/tasks/$(TASK)/restart

connect-logs: ## Show Kafka Connect container logs
	@echo "$(GREEN)► Kafka Connect logs:$(NC)"
	cd $(ANSIBLE_DIR) && ansible kafka_connect -a "docker logs kafka-connect --tail 100" --become

connect-logs-follow: ## Follow Kafka Connect logs in real-time
	@echo "$(GREEN)► Following Kafka Connect logs (Ctrl+C to stop)...$(NC)"
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	ssh -i $(SSH_KEY) ubuntu@$$IP "docker logs -f kafka-connect"

connect-validate: ## Validate connector config
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	curl -s -X PUT http://$$CONNECT_IP:8083/connector-plugins/HttpSourceConnector/config/validate \
		-H "Content-Type: application/json" \
		-d '$(CONFIG)' | jq

connect-create-http-source: ## Create HTTP Source Connector polling topics API
	@echo "$(GREEN)► Creating HTTP Source Connector...$(NC)"
	@CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.private_ip'); \
	curl -s -X POST http://$$CONNECT_IP:8083/connectors \
		-H "Content-Type: application/json" \
		-d '{"name":"http-source-topics","config":{"connector.class":"com.github.castorm.kafka.connect.http.HttpSourceConnector","tasks.max":"1","http.request.url":"http://'$$PLATFORM_IP':2020/topics","http.request.method":"GET","http.timer.interval.millis":"60000","kafka.topic":"topic-1","http.response.record.mapper":"com.github.castorm.kafka.connect.http.record.SchemedKvSourceRecordMapper","http.response.record.mapper.regex.key":".*","http.response.record.mapper.regex.value":".*"}}' | jq

# =============================================================================
# SSH ACCESS
# =============================================================================
ssh-broker: ## SSH to broker (usage: make ssh-broker or make ssh-broker N=2)
	@N=$${N:-1}; \
	IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r ".brokers.public_ips[$$((N-1))]"); \
	echo "$(GREEN)► Connecting to broker-$$N ($$IP)...$(NC)"; \
	ssh -i $(SSH_KEY) ubuntu@$$IP

ssh-controller: ## SSH to controller (usage: make ssh-controller or make ssh-controller N=2)
	@N=$${N:-1}; \
	IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r ".controllers.public_ips[$$((N-1))]"); \
	echo "$(GREEN)► Connecting to controller-$$N ($$IP)...$(NC)"; \
	ssh -i $(SSH_KEY) ubuntu@$$IP

ssh-platform: ## SSH to platform node
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	echo "$(GREEN)► Connecting to platform ($$IP)...$(NC)"; \
	ssh -i $(SSH_KEY) ubuntu@$$IP

ssh-connect: ## SSH to Kafka Connect node
	@IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	echo "$(GREEN)► Connecting to kafka-connect ($$IP)...$(NC)"; \
	ssh -i $(SSH_KEY) ubuntu@$$IP

# =============================================================================
# FULL WORKFLOWS
# =============================================================================
all: infra-apply inventory ansible-ping ## Full setup: infrastructure + inventory + connectivity test
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║              INFRASTRUCTURE READY!                           ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. make kafka-deploy        # Deploy Kafka cluster (~15-25 min)"
	@echo "  2. make kafka-create-topics"
	@echo "  3. make node-exporter-deploy"
	@echo "  4. make jmx-exporter-deploy"
	@echo "  5. make monitoring-deploy"
	@echo "  6. make api-deploy"
	@echo "  7. make connect-deploy"
	@echo ""
	@echo "Or run: $(GREEN)make deploy-all$(NC) (does all of the above)"
	@echo ""

deploy-all: kafka-deploy kafka-create-topics node-exporter-deploy jmx-exporter-deploy monitoring-deploy api-deploy connect-deploy ## Deploy all components after infrastructure
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║              FULL DEPLOYMENT COMPLETE!                       ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@$(MAKE) urls

status: ## Show status of all components
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                    SYSTEM STATUS                             ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)► Infrastructure IPs:$(NC)"
	@cd $(TF_DIR) && terraform output -json infrastructure_summary 2>/dev/null | jq '{brokers: .brokers.public_ips, controllers: .controllers.public_ips, kafka_connect: .kafka_connect.public_ip, platform: .platform.public_ip}' || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)► Kafka Brokers:$(NC)"
	@-cd $(ANSIBLE_DIR) && ansible kafka_broker -a "systemctl is-active confluent-server" --become 2>/dev/null | grep -E "(broker|active|inactive)" || echo "  Not deployed"
	@echo ""
	@echo "$(YELLOW)► Kafka Controllers:$(NC)"
	@-cd $(ANSIBLE_DIR) && ansible kafka_controller -a "systemctl is-active confluent-kcontroller" --become 2>/dev/null | grep -E "(controller|active|inactive)" || echo "  Not deployed"
	@echo ""
	@echo "$(YELLOW)► Monitoring Stack:$(NC)"
	@-cd $(ANSIBLE_DIR) && ansible platform -a "docker ps --format 'table {{.Names}}\t{{.Status}}'" --become 2>/dev/null | grep -v "NAMES" || echo "  Not deployed"
	@echo ""
	@echo "$(YELLOW)► Kafka Connect:$(NC)"
	@-cd $(ANSIBLE_DIR) && ansible kafka_connect -a "docker ps --format 'table {{.Names}}\t{{.Status}}'" --become 2>/dev/null | grep -v "NAMES" || echo "  Not deployed"
	@echo ""

validate: infra-validate api-lint ## Validate all configurations
	@echo "$(GREEN)✓ All validations passed$(NC)"

clean: ## Stop all services (keeps infrastructure)
	@echo "$(YELLOW)► Stopping all services...$(NC)"
	-cd $(ANSIBLE_DIR) && ansible platform -a "cd /opt/monitoring && docker compose down" --become 2>/dev/null
	-cd $(ANSIBLE_DIR) && ansible kafka_connect -a "cd /opt/kafka-connect && docker compose down" --become 2>/dev/null
	-cd $(ANSIBLE_DIR) && ansible platform -a "docker stop kafka-admin-api && docker rm kafka-admin-api" --become 2>/dev/null
	@echo "$(GREEN)✓ Services stopped$(NC)"

clean-all: clean kafka-stop ## Stop everything including Kafka services
	@echo "$(GREEN)✓ All services stopped$(NC)"

# =============================================================================
# UTILITIES
# =============================================================================
fix-hosts: ## Fix /etc/hosts on all nodes with private IPs
	@echo "$(GREEN)► Fixing /etc/hosts...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/fix-hosts.yml

setup-hosts: ## Setup /etc/hosts with current public IPs
	@echo "$(GREEN)► Setting up /etc/hosts...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-hosts.yml

update-sg: ## Update security group with your current IP
	@echo "$(GREEN)► Updating security group with current IP...$(NC)"
	cd $(TF_DIR) && terraform apply -auto-approve -target=module.compute.aws_security_group.kafka_cluster

urls: ## Show all service URLs
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                    SERVICE URLS                              ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@PLATFORM_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.platform.public_ip'); \
	CONNECT_IP=$$(cd $(TF_DIR) && terraform output -json infrastructure_summary | jq -r '.kafka_connect.public_ip'); \
	echo "  $(YELLOW)Grafana:$(NC)         http://$$PLATFORM_IP:3000  (admin/admin123)"; \
	echo "  $(YELLOW)Prometheus:$(NC)      http://$$PLATFORM_IP:9090"; \
	echo "  $(YELLOW)Alertmanager:$(NC)    http://$$PLATFORM_IP:9093"; \
	echo "  $(YELLOW)Kafka Admin API:$(NC) http://$$PLATFORM_IP:2020"; \
	echo "  $(YELLOW)Kafka Connect:$(NC)   http://$$CONNECT_IP:8083"
	@echo ""

logs: ## Show available log commands
	@echo "$(YELLOW)Available log commands:$(NC)"
	@echo "  make kafka-logs-broker"
	@echo "  make kafka-logs-controller"
	@echo "  make monitoring-logs"
	@echo "  make api-logs"
	@echo "  make connect-logs"
	@echo ""
	@echo "$(YELLOW)For live logs (follow):$(NC)"
	@echo "  make kafka-logs-broker-follow"
	@echo "  make api-logs-follow"
	@echo "  make connect-logs-follow"

# =============================================================================
# DEVELOPMENT HELPERS
# =============================================================================
dev-api: ## Run API locally for development
	@echo "$(GREEN)► Running API locally...$(NC)"
	cd $(API_DIR) && KAFKA_BOOTSTRAP_SERVERS=localhost:9092 go run ./cmd/api

dev-api-docker: ## Run API in Docker locally
	@echo "$(GREEN)► Running API in Docker...$(NC)"
	cd $(API_DIR) && docker run -p 2020:2020 \
		-e KAFKA_BOOTSTRAP_SERVERS=host.docker.internal:9092 \
		kafka-admin-api:1.0.0
