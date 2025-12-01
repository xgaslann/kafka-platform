#!/bin/bash
set -e
set -x

exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Setting hostname to ${hostname}"
hostnamectl set-hostname ${hostname}
echo "127.0.0.1 ${hostname}" >> /etc/hosts

echo "Setting timezone to Europe/Istanbul"
timedatectl set-timezone Europe/Istanbul

echo "Updating system packages"
apt-get update -y

echo "Installing essential packages"
apt-get install -y curl wget vim htop net-tools jq unzip

echo "Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "Increasing file descriptor limits"
cat >> /etc/security/limits.conf << EOF
*    soft nofile 65536
*    hard nofile 65536
*    soft nproc  65536
*    hard nproc  65536
EOF

echo "Tuning kernel parameters"
cat >> /etc/sysctl.conf << EOF
vm.swappiness = 1
vm.max_map_count = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
EOF

sysctl -p

echo "Installing Docker"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu

echo "Installing Docker Compose standalone"
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Installing node_exporter"
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

echo "Creating node_exporter systemd service"
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "Creating Kafka Connect directories"
mkdir -p /opt/kafka-connect
chown -R ubuntu:ubuntu /opt/kafka-connect

echo "User data script completed successfully"
touch /var/log/user-data-completed
