# Section 2: Kafka Cluster

> cp-ansible - KRaft mode

## About

Kafka cluster is deployed using Confluent's official Ansible collection (cp-ansible). The cluster runs in KRaft mode - no ZooKeeper dependency. This is the new standard for Kafka 4.x and beyond.

Security is configured with SASL_SSL and SCRAM-SHA-512 authentication. Self-signed certificates are used for development, but the setup is ready for proper CA certificates in production.

Sensitive credentials are stored in Ansible Vault.

## Overview

- Confluent Platform 8.1.0 (Kafka 4.1.0)
- KRaft mode
- 3 Controllers + 3 Brokers
- SASL_SSL + SCRAM-SHA-512

## Version Requirements

| Tool | Version |
|------|---------|
| Python | 3.10-3.12 |
| Ansible | 9.x-11.x |

## Cluster

| Node | ID | Port |
|------|-----|------|
| controller-1 | 9991 | 9093 |
| controller-2 | 9992 | 9093 |
| controller-3 | 9993 | 9093 |
| broker-1 | 1 | 9091, 9092 |
| broker-2 | 2 | 9091, 9092 |
| broker-3 | 3 | 9091, 9092 |

## Configuration

**ansible.cfg**
```ini
[defaults]
inventory = inventory/hosts.yml
hash_behaviour = merge
private_key_file = ~/.ssh/kafka-platform-key
remote_user = ubuntu
```

**group_vars/all.yml**
```yaml
confluent_package_version: "8.1.0"
kafka_controller_enabled: true

ssl_enabled: true
sasl_protocol: scram512
ssl_self_signed: true

sasl_scram_users:
  admin:
    principal: admin
    password: "{{ vault_kafka_admin_password }}"
  kafka:
    principal: kafka
    password: "{{ vault_kafka_broker_password }}"
  client:
    principal: client
    password: "{{ vault_kafka_client_password }}"

kafka_broker_custom_properties:
  default.replication.factor: 3
  min.insync.replicas: 2
  num.partitions: 3
```

**group_vars/secrets.yml** (Ansible Vault encrypted)

```bash
# Create vault file
ansible-vault create group_vars/secrets.yml

# Vault password: KafkaPlatform2025!Vault
```

```yaml
vault_kafka_admin_password: "Admin123!secure"
vault_kafka_broker_password: "Kafka123!secure"
vault_kafka_client_password: "Client123!secure"
```

> Edit existing vault: `ansible-vault edit group_vars/secrets.yml`

## /etc/hosts

> Nodes must resolve each other via private IP.

```yaml
# playbooks/fix-hosts.yml
- name: Configure /etc/hosts
  hosts: all
  become: true
  tasks:
    - name: Add cluster nodes
      lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
      loop:
        - "10.0.101.10 controller-1"
        - "10.0.102.10 controller-2"
        - "10.0.103.10 controller-3"
        - "10.0.101.166 broker-1"
        - "10.0.102.239 broker-2"
        - "10.0.103.53 broker-3"
```

## Deployment

```bash
cd 2-configuration
source ../.venv/bin/activate

ansible-playbook -i inventory/hosts.yml playbooks/fix-hosts.yml
ansible-playbook -i inventory/hosts.yml confluent.platform.all --ask-vault-pass
```

> Vault password: `KafkaPlatform2025!Vault`

## Services

| Node | Service |
|------|---------|
| Controller | confluent-kcontroller |
| Broker | confluent-server |

```bash
sudo systemctl status confluent-server
sudo journalctl -u confluent-server -f
```

## JMX Exporter

JMX Exporter installed separately for Prometheus metrics. See [Observability](./03-observability.md).

| Node | Port |
|------|------|
| Broker | 9999 |
| Controller | 9998 |

## Verification

SSH into a broker and check cluster status:

```bash
ssh -i ~/.ssh/kafka-platform-key ubuntu@<BROKER_IP>
```

```bash
kafka-metadata-quorum --bootstrap-server localhost:9091 describe --status
```

```
ClusterId:              U3JldDSNTRmESmMDCnkNOA
LeaderId:               9993
LeaderEpoch:            3
HighWatermark:          17596
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   157
CurrentVoters:          [{"id": 9991, ...}, {"id": 9992, ...}, {"id": 9993, ...}]
CurrentObservers:       [{"id": 1, ...}, {"id": 2, ...}, {"id": 3, ...}]
```

> 3 voters (controllers) and 3 observers (brokers) = cluster is healthy.

```bash
kafka-topics --bootstrap-server localhost:9091 --list
```

```
__internal_confluent_only_broker_info
_confluent-command
_confluent-link-metadata
_confluent-telemetry-metrics
test-topic
```

> Internal topics created by Confluent Platform + test-topic I created for testing.

---

**Next:** [Observability](./03-observability.md)