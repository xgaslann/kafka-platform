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
  --cidr "<NEW_PUBLIC_IP>/32"
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

---

## Checklist Before Running Playbook

Things I check now before running ansible:

- [ ] `which ansible` shows .venv/bin/ansible
- [ ] hash_behaviour = merge in ansible.cfg
- [ ] `ansible all -m ping` works
- [ ] /etc/hosts has private IPs (not public)
- [ ] Security group allows 9091-9093 from VPC
- [ ] My IP is in security group for SSH