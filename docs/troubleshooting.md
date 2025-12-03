# Troubleshooting

## About

Issues encountered during setup and how they were fixed.

---

## Issue 1: SSH Connection Timeout

**Command:**
```bash
ssh -i ~/.ssh/kafka-platform-key ubuntu@3.79.113.179
```

**Error:**
```
ssh: connect to host 3.79.113.179 port 22: Operation timed out
```

**Cause:** ISP changed IP address. Security group only allows SSH from specific IP.

**Solution:**
```bash
# Check new IP
curl -s ifconfig.me

# Add to security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-0fb88a5b26c116cea \
  --protocol tcp \
  --port 22 \
  --cidr "NEW_IP/32"
```

---

## Issue 2: Ansible Hash Merging Error

**Error:**
```
TASK [Verify Hash Merging]
fatal: [controller-1]: FAILED! => {
    "assertion": "lookup('config', 'DEFAULT_HASH_BEHAVIOUR') == 'merge'",
    "msg": "Hash Merging must be enabled in ansible.cfg"
}
```

**Cause:** cp-ansible requires hash_behaviour=merge.

**Solution:** Add to ansible.cfg:
```ini
[defaults]
hash_behaviour = merge
```

---

## Issue 3: Wrong Python/Ansible Version

**Cause:** System Python/Ansible instead of venv versions. cp-ansible 8.1 requires Python 3.10-3.12 and Ansible 9.x-11.x.

**Solution:**
```bash
# Ensure you're in venv
which ansible  # Should show .venv/bin/ansible

# If not:
source .venv/bin/activate
```

---

## Issue 4: Broker Can't Resolve Controller Hostname

**Error:**
```
WARN Couldn't resolve server controller-1:9093 from bootstrap.servers
as DNS resolution failed for controller-1
```

**Cause:** /etc/hosts file empty. Nodes can't find each other by hostname.

**Solution:**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/fix-hosts.yml
```

---

## Issue 5: Controller Connection Timeout

**Command:**
```bash
nc -zv controller-1 9093 -w 5
```

**Error:**
```
nc: connect to controller-1 (3.125.6.45) port 9093 (tcp) timed out
```

**Cause:** 
1. /etc/hosts had public IPs, but security group only allows VPC traffic (10.0.0.0/16)
2. Port 9093 wasn't open in security group

**Solution:**
1. Update /etc/hosts with private IPs:
```
10.0.101.10 controller-1   # NOT 3.125.6.45
```

2. Add port to security group:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0fb88a5b26c116cea \
  --protocol tcp \
  --port 9091-9093 \
  --cidr 10.0.0.0/16
```

---

## Issue 6: Service Name Confusion

**Error:**
```
Unit confluent-kafka.service not found
```

**Actual service names:**

| Component | Service Name |
|-----------|--------------|
| Controller | confluent-kcontroller |
| Broker | confluent-server |
| Connect | confluent-kafka-connect |

---

## Issue 7: Ansible Callback Plugin Error

**Error:**
```
[ERROR]: The 'community.general.yaml' callback plugin has been removed.
```

**Solution:** Change ansible.cfg:
```ini
# Old
stdout_callback = yaml

# New
stdout_callback = ansible.builtin.default
result_format = yaml
```

---

## Issue 8: Broker OOM Kill

**Error:**
```
Active: failed (Result: oom-kill)
```

**Cause:** Kafka + JMX Exporter using too much memory on t3.small (2GB RAM).

**Solution:**
```bash
sudo systemctl restart confluent-server
```

If persistent, upgrade instance type to m7i-flex.large (8GB RAM).

---

## Issue 9: REST API DNS Resolution Error

**Error:**
```
Failed to resolve 'broker-1:9092': Try again
```

**Cause:** Kafka brokers return hostnames in metadata via `advertised.listeners`. Platform node cannot resolve them.

**Solution:**
```bash
# Add to platform node /etc/hosts
ssh -i ~/.ssh/kafka-platform-key ubuntu@<PLATFORM_IP> "sudo tee -a /etc/hosts << HOSTS
10.0.101.166 broker-1
10.0.102.239 broker-2
10.0.103.53 broker-3
HOSTS"

# Restart container
docker restart kafka-admin-api
```

---

## Issue 10: REST API Metadata Timeout

**Error:**
```json
{"error":"get metadata: Local: Timed out"}
```

**Cause:** Docker container cannot reach Kafka brokers.

**Solution:** Run container with `--network host`:
```bash
docker run -d --network host -e KAFKA_BOOTSTRAP_SERVERS=... kafka-admin-api:1.0.0
```

---

## Issue 11: IP Address Changed - Cannot Access Services

**Symptom:** Cannot access Prometheus, Grafana, SSH after IP change.

**Cause:** Security group rules tied to specific IP addresses.

**Solution:**
```bash
# Get new IP
NEW_IP=$(curl -s ifconfig.me)

# Remove old IP
aws ec2 revoke-security-group-ingress --group-id sg-0fb88a5b26c116cea --protocol tcp --port 22 --cidr OLD_IP/32

# Add new IP for all ports
aws ec2 authorize-security-group-ingress --group-id sg-0fb88a5b26c116cea --protocol tcp --port 22 --cidr $NEW_IP/32
aws ec2 authorize-security-group-ingress --group-id sg-0fb88a5b26c116cea --protocol tcp --port 9090 --cidr $NEW_IP/32
aws ec2 authorize-security-group-ingress --group-id sg-0fb88a5b26c116cea --protocol tcp --port 3000 --cidr $NEW_IP/32
aws ec2 authorize-security-group-ingress --group-id sg-0fb88a5b26c116cea --protocol tcp --port 9093 --cidr $NEW_IP/32
```

---

## Issue 12: AWS vCPU Limit Exceeded

**Error:**
```
VcpuLimitExceeded: You have requested more vCPU capacity than your current vCPU limit of 16
```

**Cause:** AWS accounts have default vCPU limits per instance family.

**Solution:**
```bash
# Check current usage
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceType,State.Name]' --output table
```

Options:
- Stop unused instances
- Use smaller instance types  
- Request limit increase via AWS console

---

## Issue 13: Kafka Connect Instance Freeze

**Symptom:** SSH hangs, container unresponsive, instance not responding.

**Cause:** Memory exhaustion (t3.small has only 2GB RAM).

**Solution:**
```bash
# Force stop and start
aws ec2 stop-instances --instance-ids <INSTANCE_ID> --force
aws ec2 wait instance-stopped --instance-ids <INSTANCE_ID>
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Get new public IP
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

If persists, upgrade instance type to m7i-flex.large (8GB RAM).

---

## Issue 14: JMX Exporter Port Conflict

**Error:**
```
Port already in use: 9997
java.net.BindException: Address already in use
```

**Cause:** KAFKA_JMX_PORT and JMX Exporter trying to use same port.

**Solution:** Use different port (7071) for JMX Exporter and remove KAFKA_JMX_PORT:
```yaml
environment:
  # Remove: KAFKA_JMX_PORT: 9997
  EXTRA_ARGS: -javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=7071:/opt/jmx-exporter/kafka-connect.yml
```

---

## Issue 15: Prometheus Target Down After IP Change

**Symptom:** Prometheus shows targets as DOWN after instance recreation.

**Cause:** Private IP changed but Prometheus config has old IP.

**Solution:**
```bash
# Update prometheus.yml with new IPs
ssh ubuntu@<PLATFORM_IP> "sudo nano /opt/monitoring/prometheus/prometheus.yml"

# Restart prometheus
ssh ubuntu@<PLATFORM_IP> "docker restart prometheus"
```

---

## Issue 16: HTTP Source Connector Not Found

**Error:**
```
Error: Component not found, specify either valid name from Confluent Hub
```

**Cause:** castorm/kafka-connect-http not on Confluent Hub or wrong version format.

**Solution:** Manual installation:
```bash
cd /tmp
wget https://github.com/castorm/kafka-connect-http/releases/download/v0.8.11/kafka-connect-http-0.8.11-plugin.tar.gz
tar -xzf kafka-connect-http-0.8.11-plugin.tar.gz
docker cp kafka-connect-http kafka-connect:/usr/share/confluent-hub-components/
docker restart kafka-connect
```

---

## Debug Commands
```bash
# Service status
sudo systemctl status confluent-server
sudo systemctl status confluent-kcontroller

# View logs
sudo journalctl -u confluent-server -n 50 --no-pager

# Check listening ports
sudo ss -tlnp | grep 909

# Test connectivity
nc -zv controller-1 9093 -w 5
nc -zv broker-1 9091 -w 5

# Check /etc/hosts
cat /etc/hosts | grep -E 'controller|broker'

# Cluster status
kafka-metadata-quorum --bootstrap-server localhost:9091 describe --status

# Docker logs
docker logs kafka-connect --tail 50
docker logs kafka-admin-api --tail 50

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

---

## IP Change Checklist

When instances restart or get recreated:

### Public IP Changed (Spot restart)
```bash
# 1. Get new IPs
cd 1-infrastructure/envs/dev
terraform output -json | jq '.infrastructure_summary.value'

# 2. Update hosts.yml
nano ../../../2-configuration/inventory/hosts.yml

# 3. Test Ansible connectivity
cd ../../../2-configuration
ansible all -m ping
```

### Private IP Changed (Instance recreate)
```bash
# 1. Get new IPs
terraform output -json | jq '.infrastructure_summary.value'

# 2. Update these files:
# - 2-configuration/playbooks/fix-hosts.yml
# - 4-platform/monitoring-stack/prometheus/prometheus.yml
# - 4-platform/monitoring-stack/grafana/provisioning/dashboards/*.json (instance regex)

# 3. Update /etc/hosts on all nodes
ansible-playbook -i inventory/hosts.yml playbooks/fix-hosts.yml

# 4. Restart Prometheus
ssh ubuntu@<PLATFORM_IP> "cd /opt/monitoring && docker compose restart prometheus"
```

### Files to Update

| Scenario | File | What to Update |
|----------|------|----------------|
| Public IP changed | `inventory/hosts.yml` | ansible_host values |
| Private IP changed | `playbooks/fix-hosts.yml` | /etc/hosts entries |
| Private IP changed | `prometheus/prometheus.yml` | scrape targets |
| Private IP changed | `grafana/dashboards/*.json` | instance regex patterns |
| Private IP changed | `playbooks/kafka-admin-api.yml` | kafka_bootstrap value |

### Static IPs (Never Change)

Controllers use static IPs (required for KRaft quorum):
- controller-1: 10.0.101.10
- controller-2: 10.0.102.10
- controller-3: 10.0.103.10

These are defined in Terraform and remain the same even if instance is recreated.

## Checklist Before Running Playbook

- [ ] `which ansible` shows .venv/bin/ansible
- [ ] hash_behaviour = merge in ansible.cfg
- [ ] `ansible all -m ping` works
- [ ] /etc/hosts has private IPs (not public)
- [ ] Security group allows 9091-9093 from VPC
- [ ] My IP is in security group for SSH
- [ ] Broker hostnames in platform node /etc/hosts
