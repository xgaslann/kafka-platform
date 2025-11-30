locals {


  controller_quorum_voters = join(",", [
    for i in range(var.controller_count) :
    "${i + 1}@${var.controller_ips[i]}:9093"
  ])

  kafka_cluster_id = "wWdXO5P7Somh-WdtnlUdKw"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "kafka_cluster" {
  description = "Security group for Kafka cluster"
  name_prefix = "${var.project_name}-kafka-sg-"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH access from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "Kafka Admin REST API"
    from_port   = 2020
    to_port     = 2020
    protocol    = "tcp"
    cidr_blocks = var.public_api_cidr_blocks
  }

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "Kafka Connect REST API"
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Prometheus web interface"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-kafka-sg"
    Project     = var.project_name
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "kafka_broker" {
  count = var.broker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.broker_instance_type
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.kafka_cluster.id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-broker-${count.index + 1}-root"
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user-data-broker.sh", {
    hostname                 = "broker-${count.index + 1}"
    broker_id                = count.index + 4
    rack_id                  = "az-${(count.index % 3) + 1}"
    project_name             = var.project_name
    controller_quorum_voters = local.controller_quorum_voters
    kafka_cluster_id         = local.kafka_cluster_id
  }))

  tags = {
    Name        = "${var.project_name}-broker-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    Role        = "kafka-broker"
    Rack        = "az-${(count.index % 3) + 1}"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_instance.kafka_controller]
}

resource "aws_instance" "kafka_controller" {
  count = var.controller_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.controller_instance_type
  private_ip             = var.controller_ips[count.index]
  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.kafka_cluster.id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 15
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-controller-${count.index + 1}-root"
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user-data-controller.sh", {
    hostname                 = "controller-${count.index + 1}"
    controller_id            = count.index + 1
    controller_quorum_voters = local.controller_quorum_voters
    kafka_cluster_id         = local.kafka_cluster_id
    project_name             = var.project_name
  }))

  tags = {
    Name        = "${var.project_name}-controller-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    Role        = "kafka-controller"
    NodeID      = count.index + 1
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "platform" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.platform_instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.kafka_cluster.id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-platform-root"
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user-data-platform.sh", {
    hostname     = "platform"
    project_name = var.project_name
  }))

  tags = {
    Name        = "${var.project_name}-platform"
    Project     = var.project_name
    Environment = var.environment
    Role        = "platform"
    Services    = "monitoring,kafka-connect,rest-api"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_instance.kafka_controller, aws_instance.kafka_broker]
}
