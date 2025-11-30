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
mkdir -p /var/lib/kafka/data
mkdir -p /var/log/kafka
mkdir -p /opt/kafka

chown -R kafka:kafka /var/lib/kafka
chown -R kafka:kafka /var/log/kafka
chown -R kafka:kafka /opt/kafka


echo "CONTROLLER_ID=${controller_id}" >> /etc/environment

echo "Downloading Kafka 3.9.0"
cd /tmp
wget -q https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz

echo "Extracting Kafka"
tar -xzf kafka_2.13-3.9.0.tgz -C /opt/kafka --strip-components=1
chown -R kafka:kafka /opt/kafka

CONTROLLER_ID_VALUE=${controller_id}
CONTROLLER_QUORUM_VOTERS="${controller_quorum_voters}"

echo "Creating Kafka controller configuration"
cat > /opt/kafka/config/kraft/controller.properties << EOF
process.roles=controller
node.id=$CONTROLLER_ID_VALUE
controller.quorum.voters=$CONTROLLER_QUORUM_VOTERS
listeners=CONTROLLER://:9093
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
log.dirs=/var/lib/kafka/data
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
EOF

chown kafka:kafka /opt/kafka/config/kraft/controller.properties

echo "Creating systemd service"
cat > /etc/systemd/system/kafka-controller.service << 'EOF'
[Unit]
Description=Apache Kafka Controller
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="KAFKA_HEAP_OPTS=-Xmx512M -Xms512M"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/controller.properties
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kafka-controller

[Install]
WantedBy=multi-user.target
EOF

echo "Formatting Kafka storage"
KAFKA_CLUSTER_ID="${kafka_cluster_id}"
sudo -u kafka bash -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && /opt/kafka/bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -c /opt/kafka/config/kraft/controller.properties"

echo "Enabling and starting Kafka controller service"
systemctl daemon-reload
systemctl enable kafka-controller
systemctl start kafka-controller

echo "User data script completed successfully"
touch /var/log/user-data-completed