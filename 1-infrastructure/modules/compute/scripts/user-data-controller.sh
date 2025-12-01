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
net.ipv4.tcp_max_syn_backlog = 8096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
EOF

sysctl -p

echo "Installing Java 17"
apt-get install -y openjdk-17-jdk

echo "Configuring environment variables"
cat >> /etc/environment << 'EOF'
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:/usr/lib/jvm/java-17-openjdk-amd64/bin
EOF

echo "Creating kafka user"
useradd -r -s /bin/bash -d /opt/kafka kafka

echo "Creating Kafka directories"
mkdir -p /var/lib/kafka/metadata
mkdir -p /var/log/kafka
mkdir -p /opt/kafka

chown -R kafka:kafka /var/lib/kafka
chown -R kafka:kafka /var/log/kafka
chown -R kafka:kafka /opt/kafka

echo "Setting environment variable for Controller"
echo "CONTROLLER_ID=${controller_id}" >> /etc/environment

echo "User data script completed successfully"
touch /var/log/user-data-completed
