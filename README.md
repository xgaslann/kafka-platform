# Kafka Platform

> Production-ready Kafka cluster on AWS with IaC and automation

## About

This project demonstrates building a production-grade data streaming platform from scratch. Everything is automated - infrastructure provisioning with Terraform, Kafka cluster deployment with Ansible, monitoring with Prometheus/Grafana, and a REST API for cluster management.

The goal is to have a fully functional, observable, and maintainable Kafka setup that you can spin up with a few commands.

## What's inside?

- Section 1: Infrastructure as Code (Terraform)
- Section 2: Kafka Cluster Setup (cp-ansible, KRaft mode)
- Section 3: Observability Stack (Prometheus, Grafana, Alertmanager)
- Section 4: REST API (Go + Kafka AdminClient)
- Section 5: Kafka Connect (Docker Compose)

## Cluster Overview

> 8 nodes on AWS (eu-central-1)

| Node | Count | Description |
|------|-------|-------------|
| Controller | 3 | KRaft quorum (1 per AZ) |
| Broker | 3 | Kafka broker (1 per AZ) |
| Kafka Connect | 1 | Data integration |
| Platform | 1 | Monitoring stack |

## Versions

| Tool | Version |
|------|---------|
| Confluent Platform | 8.1.0 |
| Apache Kafka | 4.1.0 |
| cp-ansible | 8.1.0 |
| Ansible | 10.6.0 |
| Python | 3.12.7 |
| Terraform | >= 1.0 |

## Project Structure

```
kafka-platform/
├── 1-infrastructure/       # Terraform
│   ├── envs/dev/
│   └── modules/
├── 2-configuration/        # Ansible
│   ├── inventory/
│   ├── group_vars/
│   └── playbooks/
├── 3-services/             # Go REST API
├── 4-platform/             # Monitoring + Kafka Connect
└── docs/
```

## Prerequisites

> Check [Installation Guide](./INSTALLATION.md) first.

## Quick Start

```bash
# 1. Python environment
pyenv local 3.12.7
python -m venv .venv
source .venv/bin/activate
pip install ansible==10.6.0
ansible-galaxy collection install confluent.platform:8.1.0

# 2. Terraform
cd 1-infrastructure/envs/dev
terraform init && terraform apply

# 3. Ansible (vault password: KafkaPlatform2025!Vault)
cd ../../2-configuration
ansible-playbook -i inventory/hosts.yml confluent.platform.all --ask-vault-pass

# 4. Verify
ssh -i ~/.ssh/kafka-platform-key ubuntu@<BROKER_IP> \
  "kafka-metadata-quorum --bootstrap-server localhost:9091 describe --status"
```

## Getting Started

> Follow in order:

1. [Installation Guide](./INSTALLATION.md) - local setup
2. [Infrastructure](./docs/01-infrastructure.md) - Terraform
3. [Kafka Cluster](./docs/02-kafka-cluster.md) - cp-ansible
4. [Observability](./docs/03-observability.md) - Prometheus, Grafana
5. [REST API](./docs/04-rest-api.md) *(will be updated)*
6. [Kafka Connect](./docs/05-kafka-connect.md) *(will be updated)*

> Having issues? Check [Troubleshooting](./docs/troubleshooting.md)

## Screenshots

> See [docs/screenshots](./docs/screenshots/) for AWS console and monitoring screenshots.

| Screenshot                                                            | Description |
|-----------------------------------------------------------------------|-------------|
| [EC2 Dashboard](./docs/screenshots/ec2_dashboard.png)                 | Running instances |
| [Security Groups](./docs/screenshots/security_groups.png)             | Inbound rules |
| [VPC Subnets](./docs/screenshots/vpc_subnets_1.png)                   | Subnet configuration |
| [Prometheus Target_1](./docs/screenshots/prometheus_target_1.png)     | Monitoring targets |
| [Prometheus Target_2](./docs/screenshots/prometheus_target_2.png)     | Monitoring targets |
| [Grafana Broker](./docs/screenshots/grafana_kafka_broker.png)         | Broker dashboard |
| [Grafana Controller](./docs/screenshots/grafana_kafka_controller.png) | Controller dashboard |