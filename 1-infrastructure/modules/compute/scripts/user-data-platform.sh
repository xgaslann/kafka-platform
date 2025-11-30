#!/bin/bash
# shellcheck disable=SC2154
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
apt-get install -y curl wget vim htop net-tools jq unzip git build-essential python3 python3-pip

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

echo "Installing Java 17"
apt-get install -y openjdk-17-jdk

echo "Configuring Java environment"
cat >> /etc/environment << 'EOF'
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
EOF

echo "Installing Go 1.25"
wget -q https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -O /tmp/go1.25.0.linux-amd64.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go1.25.0.linux-amd64.tar.gz

echo "Configuring Go environment"
cat >> /etc/environment << 'EOF'
GOROOT=/usr/local/go
GOPATH=/home/ubuntu/go
GOBIN=/home/ubuntu/go/bin
EOF

echo "export PATH=\$PATH:/usr/local/go/bin:\$GOBIN" >> /home/ubuntu/.bashrc
chown ubuntu:ubuntu /home/ubuntu/.bashrc

mkdir -p /home/ubuntu/go/{bin,src,pkg}
chown -R ubuntu:ubuntu /home/ubuntu/go

echo "Creating platform directories"
mkdir -p /opt/platform/monitoring
mkdir -p /opt/platform/kafka-connect
mkdir -p /opt/platform/rest-api

chown -R ubuntu:ubuntu /opt/platform

echo "User data script completed successfully"
touch /var/log/user-data-completed