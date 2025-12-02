# Troubleshooting

## About

Issues I encountered during setup and how I fixed them.

---

## 1. SSH Connection Timeout

I ran:
```bash
ssh -i ~/.ssh/kafka-platform-key ubuntu@3.79.113.179
```

Got:
```
ssh: connect to host 3.79.113.179 port 22: Operation timed out
```

**What happened:** My ISP changed my IP address. Security group only allows SSH from my IP.

**How I fixed it:**
```bash
# Check new IP
curl -s ifconfig.me

# Add to security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-0fb88a5b26c116cea \
  --protocol tcp \
  --port 22 \
  --cidr "159.146.17.211/32"
```

---

## 2. Ansible Hash Merging Error

I ran:
```bash
ansible-playbook -i inventory/hosts.yml confluent.platform.all
```

Got:
```
TASK [Verify Hash Merging]
fatal: [controller-1]: FAILED! => {
    "assertion": "lookup('config', 'DEFAULT_HASH_BEHAVIOUR') == 'merge'",
    "msg": "Hash Merging must be enabled in ansible.cfg"
}
```

**What happened:** cp-ansible requires hash_behaviour=merge but it wasn't in my ansible.cfg.

**How I fixed it:**

Added to ansible.cfg:
```ini
[defaults]
hash_behaviour = merge
```

---

## 3. Wrong Python/Ansible Version

I ran:
```bash
ansible-playbook -i inventory/hosts.yml confluent.platform.all
```

Got errors about incompatible modules or weird behavior.

**What happened:** I was using system Python/Ansible instead of the venv versions. cp-ansible 8.1 requires Python 3.10-3.12 and Ansible 9.x-11.x.

**How I fixed it:**
```bash
# Make sure you're in venv
which ansible  # Should show .venv/bin/ansible, not /usr/bin/ansible

# If not:
source .venv/bin/activate
```

---

## 4. Broker Can't Resolve Controller Hostname

Broker logs showed:
```
WARN Couldn't resolve server controller-1:9093 from bootstrap.servers
as DNS resolution failed for controller-1
```

**What happened:** /etc/hosts file was empty. Nodes couldn't find each other by hostname.

**How I fixed it:**

Created playbooks/fix-hosts.yml and ran it:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/fix-hosts.yml
```

This added entries like:
```
10.0.101.10 controller-1
10.0.102.10 controller-2
...
```

---

## 5. Controller Connection Timeout

I tested connectivity:
```bash
nc -zv controller-1 9093 -w 5
```

Got:
```
nc: connect to controller-1 (3.125.6.45) port 9093 (tcp) timed out
```

**What happened:** Two issues:
1. /etc/hosts had public IPs, but security group only allows traffic within VPC (10.0.0.0/16)
2. Port 9093 wasn't open in security group

**How I fixed it:**

First, updated /etc/hosts with private IPs (not public):
```
10.0.101.10 controller-1   # NOT 3.125.6.45
```

Then added port to security group:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0fb88a5b26c116cea \
  --protocol tcp \
  --port 9091-9093 \
  --cidr 10.0.0.0/16
```

---

## 6. Service Name Confusion

I ran:
```bash
sudo systemctl status confluent-kafka
```

Got:
```
Unit confluent-kafka.service not found
```

**What happened:** Service names are different than expected.

**Actual service names:**

| Component | Service Name |
|-----------|--------------|
| Controller | confluent-kcontroller |
| Broker | confluent-server |
| Connect | confluent-kafka-connect |

---

## 7. Ansible Callback Plugin Error

I ran:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/monitoring-stack.yml
```

Got:
```
[ERROR]: The 'community.general.yaml' callback plugin has been removed.
```

**What happened:** Ansible callback plugin syntax changed in newer versions.

**How I fixed it:**

Changed ansible.cfg:
```ini
# Old
stdout_callback = yaml

# New
stdout_callback = ansible.builtin.default
result_format = yaml
```

---

## 8. Broker OOM Kill

I ran:
```bash
sudo systemctl status confluent-server
```

Got:
```
Active: failed (Result: oom-kill)
```

**What happened:** Kafka + JMX Exporter using too much memory on t3.small (2GB RAM).

**How I fixed it:**

Restart the broker:
```bash
sudo systemctl restart confluent-server
```

If it keeps happening, options:
- Increase instance size
- Tune JVM heap settings
- Reduce JMX Exporter scrape interval

---

## Debug Commands

Things I used to debug:

```bash
# Check service status
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
```

## Issue 9: REST API DNS Resolution Error

**Symptom:**
```
Failed to resolve 'broker-1:9092': Try again
```

**Cause:**
Kafka brokers return hostnames (broker-1, broker-2, broker-3) in metadata response via `advertised.listeners`. The platform node cannot resolve these hostnames.

**Solution:**

Option 1 - Use existing fix-hosts playbook:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/fix-hosts.yml
```

Option 2 - Manual addition to platform node:
```bash
ssh -i ~/.ssh/kafka-platform-key ubuntu@<PLATFORM_IP> "sudo tee -a /etc/hosts << EOF
10.0.101.166 broker-1
10.0.102.239 broker-2
10.0.103.53 broker-3
10.0.101.10 controller-1
10.0.102.10 controller-2
10.0.103.10 controller-3
EOF"
```

Option 3 - Add task to kafka-admin-api.yml playbook:
```yaml
- name: Add broker hostnames to /etc/hosts
  lineinfile:
    path: /etc/hosts
    line: "{{ item }}"
  loop:
    - "10.0.101.166 broker-1"
    - "10.0.102.239 broker-2"
    - "10.0.103.53 broker-3"
```

After fixing, restart the container:
```bash
docker restart kafka-admin-api
```

**Verification:**
```bash
curl http://<PLATFORM_IP>:2020/brokers
# Should return broker list without timeout
```

## Issue 10: REST API Metadata Timeout

**Symptom:**
```json
{"error":"get metadata: Local: Timed out"}
```

**Cause:** Docker container cannot reach Kafka brokers.

**Solution:**
Run container with `--network host`:
```bash
docker run -d --network host -e KAFKA_BOOTSTRAP_SERVERS=... kafka-admin-api:1.0.0
```

---

## Checklist Before Running Playbook

Things I check now before running ansible:

- [ ] `which ansible` shows .venv/bin/ansible
- [ ] hash_behaviour = merge in ansible.cfg
- [ ] `ansible all -m ping` works
- [ ] /etc/hosts has private IPs (not public)
- [ ] Security group allows 9091-9093 from VPC
- [ ] My IP is in security group for SSH