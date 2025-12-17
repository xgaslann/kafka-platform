#!/bin/bash
# Fix IP access when your IP changes

cd ~/Projects/platform/kafka-platform/1-infrastructure/envs/dev

MY_IP=$(curl -s ifconfig.me)

# Get SG ID from instance (not terraform output)
INSTANCE_ID=$(terraform output -json infrastructure_summary | jq -r '.platform.instance_id')
SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

echo "MY IP: $MY_IP"
echo "Security Group: $SG_ID"

# Add SSH access
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr $MY_IP/32 2>/dev/null && echo "SSH (22) added" || echo "SSH already authorized"

# Add other ports
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 2020 --cidr $MY_IP/32 2>/dev/null && echo "API (2020) added" || echo "API already authorized"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr $MY_IP/32 2>/dev/null && echo "Grafana (3000) added" || echo "Grafana already authorized"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 9090 --cidr $MY_IP/32 2>/dev/null && echo "Prometheus (9090) added" || echo "Prometheus already authorized"

echo ""
echo "All ports opened for $MY_IP"