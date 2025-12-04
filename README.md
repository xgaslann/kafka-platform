# Kafka Platform

> Kafka cluster on AWS - Terraform, Ansible, Go

## About

Production-grade Kafka cluster from scratch. Wanted to build something real - not just a docker-compose file, but actual infrastructure you could run in production.

What's here:
- **Infrastructure**: Terraform for AWS (VPC, subnets across 3 AZs, EC2 instances, security groups)
- **Kafka**: cp-ansible with KRaft mode
- **Monitoring**: Full observability stack - Prometheus scraping JMX metrics, Grafana dashboards, Alertmanager for alerts
- **REST API**: Go service wrapping Kafka AdminClient - create topics, list brokers, manage consumer groups
- **Kafka Connect**: HTTP Source Connector that polls the REST API and writes to a topic

The goal was to have everything automated. Run a few commands, get a working cluster.

## Why these choices?

**KRaft mode**: Simpler architecture, one less component to manage compared to ZooKeeper setup.

**cp-ansible**: Confluent's official Ansible collection. Battle-tested, handles all the complexity of Kafka configuration. Could have done it manually but why reinvent the wheel?

**3 Controllers + 3 Brokers**: Minimum for high availability. Each in a different AZ so if one AZ goes down, cluster keeps running.

**Go for REST API**: Fast, single binary, great Kafka client library. Could have used Python but Go felt right for this.

**PLAINTEXT security**: Started with SASL_SSL but ran into certificate issues with cp-ansible. Works for demo purposes. In production you'd definitely want encryption.

## Sections

| # | Section | What I built |
|---|---------|--------------|
| 1 | Infrastructure | Terraform - VPC, EC2, Security Groups |
| 2 | Kafka Cluster | cp-ansible, KRaft mode, 3 brokers + 3 controllers |
| 3 | Observability | Prometheus, Grafana, Alertmanager, JMX Exporter |
| 4 | REST API | Go + Fiber, Kafka AdminClient, Docker deployment |
| 5 | Kafka Connect | Docker Compose, HTTP Source Connector, JMX metrics |

## Cluster Overview

8 nodes on AWS eu-central-1:

| Node | Count | Type | Description |
|------|-------|------|-------------|
| Controller | 3 | m7i-flex.large | KRaft quorum, 1 per AZ |
| Broker | 3 | m7i-flex.large | 1 per AZ |
| Kafka Connect | 1 | m7i-flex.large | HTTP Source Connector |
| Platform | 1 | t3.small | Monitoring + REST API |

Started with t3.small for brokers but kept getting OOM kills. Kafka + JMX Exporter needs more than 2GB RAM. Upgraded to m7i-flex.large (8GB) and problems went away.

## Nodes

> ⚠️ **IP Addresses May Change!**
>
> - **Public IPs**: Change when spot instance restarts
> - **Private IPs**: Change when instance is recreated (except controllers - static IP)
>
> Files to update when IPs change:
> - `2-configuration/inventory/hosts.yml` (public IPs)
> - `2-configuration/playbooks/fix-hosts.yml` (private IPs)
> - `4-platform/monitoring-stack/prometheus/prometheus.yml` (private IPs)
> - Grafana dashboards (instance regex patterns)
>
> Get current IPs: `terraform output -json`

## Architecture
```
                            ┌─────────────────────────────────────┐
                            │           Platform Node             │
                            │  ┌───────────┐ ┌─────────────────┐  │
                            │  │ Prometheus│ │ Kafka Admin API │  │
                            │  │   :9090   │ │     :2020       │  │
                            │  └───────────┘ └─────────────────┘  │
                            │  ┌───────────┐ ┌─────────────────┐  │
                            │  │  Grafana  │ │  Alertmanager   │  │
                            │  │   :3000   │ │     :9093       │  │
                            │  └───────────┘ └─────────────────┘  │
                            └─────────────────────────────────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              │                              │                              │
              ▼                              ▼                              ▼
    ┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐
    │   AZ-1 (101)    │            │   AZ-2 (102)    │            │   AZ-3 (103)    │
    │  ┌───────────┐  │            │  ┌───────────┐  │            │  ┌───────────┐  │
    │  │controller-1│  │            │  │controller-2│  │            │  │controller-3│  │
    │  │   :9093   │  │            │  │   :9093   │  │            │  │   :9093   │  │
    │  └───────────┘  │            │  └───────────┘  │            │  └───────────┘  │
    │  ┌───────────┐  │            │  ┌───────────┐  │            │  ┌───────────┐  │
    │  │ broker-1  │  │            │  │ broker-2  │  │            │  │ broker-3  │  │
    │  │:9091/:9092│  │            │  │:9091/:9092│  │            │  │:9091/:9092│  │
    │  └───────────┘  │            │  └───────────┘  │            │  └───────────┘  │
    │  ┌───────────┐  │            └─────────────────┘            └─────────────────┘
    │  │  Connect  │  │
    │  │   :8083   │  │
    │  └───────────┘  │
    └─────────────────┘
```

All nodes communicate via private IPs. Security group only allows what's needed - Kafka ports from within VPC, monitoring ports from my IP.

## Versions

| Tool | Version |
|------|---------|
| Confluent Platform | 8.1.0 |
| Kafka | 4.1.0 |
| cp-ansible | 8.1.0 |
| Ansible | 10.6.0 |
| Python | 3.12.7 |
| Terraform | >= 1.0 |
| Go | 1.25 |

Version compatibility matters. cp-ansible 8.1 needs Ansible 9.x-11.x and Python 3.10-3.12. Spent some time debugging issues that turned out to be wrong Python version.

## Project Structure
```
kafka-platform/
├── 1-infrastructure/           # Terraform
│   ├── envs/dev/              # Environment-specific vars
│   └── modules/               # Reusable modules (vpc, compute, security)
├── 2-configuration/            # Ansible
│   ├── inventory/             # Host definitions
│   ├── group_vars/            # Kafka configuration
│   └── playbooks/             # Deployment playbooks
├── 3-services/                 # Applications
│   └── kafka-admin-api/       # Go REST API
├── 4-platform/                 # Platform components
│   └── kafka-connect/         # Docker Compose + configs
└── docs/                       # Documentation
```

## Prerequisites

Check [Installation Guide](./INSTALLATION.md) first. You'll need:
- AWS account with credentials configured
- Terraform
- Python 3.12.7 (use pyenv)
- SSH key pair

## How to Run
```bash
# 1. Python environment
pyenv local 3.12.7
python -m venv .venv
source .venv/bin/activate
pip install ansible==10.6.0
ansible-galaxy collection install confluent.platform:8.1.0

# 2. Infrastructure
cd 1-infrastructure/envs/dev
terraform init
terraform apply

# 3. Kafka cluster
cd ../../2-configuration
ansible-playbook -i inventory/hosts.yml confluent.platform.all --ask-vault-pass
# vault password: KafkaPlatform2025!Vault

# 4. Monitoring stack
ansible-playbook -i inventory/hosts.yml playbooks/monitoring-stack.yml

# 5. REST API
ansible-playbook -i inventory/hosts.yml playbooks/kafka-admin-api.yml

# 6. Kafka Connect
ansible-playbook -i inventory/hosts.yml playbooks/kafka-connect.yml
```

## Verify Everything Works
```bash
# Cluster health
ssh -i ~/.ssh/kafka-platform-key ubuntu@<BROKER_IP> \
  "kafka-metadata-quorum --bootstrap-server localhost:9091 describe --status"

# REST API
curl http://<PLATFORM_IP>:2020/brokers
curl http://<PLATFORM_IP>:2020/topics

# Prometheus targets
curl http://<PLATFORM_IP>:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Kafka Connect
curl http://<KAFKA_CONNECT_PRIVATE_IP>:8083/connectors
```

## Documentation

Follow in order:

1. [Installation Guide](./INSTALLATION.md) - local setup
2. [Infrastructure](./docs/01-infrastructure.md) - Terraform modules, what gets created
3. [Kafka Cluster](./docs/02-kafka-cluster.md) - cp-ansible config, KRaft setup
4. [Observability](./docs/03-observability.md) - Prometheus, Grafana, alerts
5. [REST API](./docs/04-rest-api.md) - Go API, endpoints, deployment
6. [Kafka Connect](./docs/05-kafka-connect.md) - HTTP Source Connector setup

Having issues? Check [Troubleshooting](./docs/troubleshooting.md) - documented every problem I ran into.

## Endpoints

| Service | Port | Access                                |
|---------|------|---------------------------------------|
| REST API | 2020 | http://platform:2020                  |
| Prometheus | 9090 | http://platform:9090                  |
| Grafana | 3000 | http://platform:3000 (admin/admin123) |
| Alertmanager | 9093 | http://platform:9093                  |
| Kafka Connect | 8083 | http://kafka-connect:8083 (VPC only)  |

Kafka Connect REST API is only accessible from within VPC. Security group doesn't expose 8083 to internet.

## REST API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| GET | /brokers | List all brokers in cluster |
| GET | /topics | List all topics with partition count |
| POST | /topics | Create new topic |
| GET | /topics/{name} | Topic details - partitions, replicas, ISR, configs |
| PUT | /topics/{name} | Update topic config (retention, etc) |
| GET | /consumer-groups | List all consumer groups |
| GET | /consumer-groups/{id} | Consumer group details - members, offsets, lag |

Example:
```bash
# Create a topic
curl -X POST http://<PLATFORM_IP>:2020/topics \
  -H "Content-Type: application/json" \
  -d '{"name": "my-topic", "partitions": 3, "replication_factor": 3}'

# Check topic details
curl http://<PLATFORM_IP>:2020/topics/my-topic
```

## Monitoring

Prometheus scrapes:
- **kafka_broker** (port 9999) - Broker JMX metrics
- **kafka_controller** (port 9998) - Controller JMX metrics  
- **kafka_connect** (port 7071) - Connect worker metrics
- **node_exporter** (port 9100) - System metrics from all nodes

Grafana has dashboards for:
- Kafka Broker - partition count, bytes in/out, request rate, ISR
- Kafka Controller - leader elections, raft commit latency
- Kafka Connect - connector status, task count, throughput

Alertmanager configured with alerts for:
- Instance down
- High memory/CPU usage
- Under-replicated partitions
- Failed connectors

## Screenshots

| Screenshot | Description |
|------------|-------------|
| [EC2 Dashboard](./docs/screenshots/ec2_dashboard.png) | All 8 instances running |
| [Security Groups](./docs/screenshots/security_groups.png) | Inbound rules |
| [VPC Subnets](./docs/screenshots/vpc_subnets.png) | 3 subnets across AZs |
| [Prometheus Targets 1](./docs/screenshots/prometheus_target_1.png) | All targets UP |
| [Prometheus Targets 2](./docs/screenshots/prometheus_target_2.png) | More targets |
| [Grafana Broker](./docs/screenshots/grafana_kafka_broker.png) | Broker metrics |
| [Grafana Controller](./docs/screenshots/grafana_kafka_controller.png) | Controller metrics |

## Lessons Learned

Some things that bit me:

1. **DNS resolution**: Kafka returns broker hostnames in metadata. If your client can't resolve them, you get timeouts. Had to add entries to /etc/hosts.

2. **JMX port conflicts**: Can't use same port for native JMX and JMX Exporter. Learned this the hard way with Kafka Connect.

3. **Instance sizing**: t3.small is not enough for Kafka. Brokers kept getting OOM killed. m7i-flex.large works.

4. **Security group changes**: When your IP changes, you lose access to everything. Keep the AWS CLI handy.

5. **cp-ansible version compatibility**: Very specific about Python and Ansible versions. Check requirements first.

6. **IP addresses change**: Spot instances get new public IPs on restart. Private IPs change if instance is recreated. Keep `terraform output` handy and update configs accordingly. Controller IPs are static (required for KRaft quorum).

All documented in [Troubleshooting](./docs/troubleshooting.md).

## Cleanup
```bash
cd 1-infrastructure/envs/dev
terraform destroy
```

This deletes everything - instances, VPC, security groups. All gone.

## Cost

I've used AWS free tier, so that's why I couldn't use all the instances. Such as a t3.medium for Kafka Connect.

Current usage: **$4.75** (as of Dec 3, 2025)

Started with $140 AWS credits, $135.25 remaining.

Running this cluster costs roughly:
- 6x m7i-flex.large: ~$0.10/hr each = $0.60/hr
- 2x t3.small: ~$0.02/hr each = $0.04/hr
- Total: ~$0.64/hr = ~$15/day

Don't forget to `terraform destroy` when you're done.
