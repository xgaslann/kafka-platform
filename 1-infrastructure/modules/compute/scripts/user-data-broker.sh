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
mkdir -p /var/lib/kafka/data
mkdir -p /var/log/kafka
mkdir -p /opt/kafka

chown -R kafka:kafka /var/lib/kafka
chown -R kafka:kafka /var/log/kafka
chown -R kafka:kafka /opt/kafka

echo "BROKER_ID=${broker_id}" >> /etc/environment
echo "RACK_ID=${rack_id}" >> /etc/environment

echo "Downloading Kafka 3.9.0"
cd /tmp
wget -q https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz

echo "Extracting Kafka"
tar -xzf kafka_2.13-3.9.0.tgz -C /opt/kafka --strip-components=1
chown -R kafka:kafka /opt/kafka

echo "Getting instance private IP from metadata"
BROKER_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Broker private IP: $BROKER_PRIVATE_IP"

echo "Creating Kafka broker configuration"
cat > /opt/kafka/config/kraft/broker.properties << EOF
process.roles=broker
node.id=${broker_id}
controller.quorum.voters=${controller_quorum_voters}
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://:9092
advertised.listeners=PLAINTEXT://$BROKER_PRIVATE_IP:9092
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
log.dirs=/var/lib/kafka/data
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.partitions=3
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
broker.rack=${rack_id}
EOF

chown kafka:kafka /opt/kafka/config/kraft/broker.properties

echo "Creating systemd service"
cat > /etc/systemd/system/kafka-broker.service << 'EOF'
[Unit]
Description=Apache Kafka Broker
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="KAFKA_HEAP_OPTS=-Xmx1G -Xms1G"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/broker.properties
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kafka-broker

[Install]
WantedBy=multi-user.target
EOF

echo "Formatting Kafka storage"
sudo -u kafka bash -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && /opt/kafka/bin/kafka-storage.sh format -t ${kafka_cluster_id} -c /opt/kafka/config/kraft/broker.properties"

echo "Enabling and starting Kafka broker service"
systemctl daemon-reload
systemctl enable kafka-broker
systemctl start kafka-broker

echo "User data script completed successfully"
touch /var/log/user-data-completed