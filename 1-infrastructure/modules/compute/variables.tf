variable "controller_ips" {
  description = "Static IPs for Kafka controllers (required for KRaft quorum)"
  type        = list(string)
  default = [
    "10.0.0.10",
    "10.0.1.10",
    "10.0.2.10"
  ]
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from network module"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for security group rules)"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs from network module"
  type        = list(string)
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "broker_count" {
  description = "Number of Kafka broker instances"
  type        = number
  default     = 4

  validation {
    condition     = var.broker_count >= 3
    error_message = "At least 3 brokers required for production setup"
  }
}

variable "broker_instance_type" {
  description = "EC2 instance type for brokers"
  type        = string
  default     = "t3.small"
}

variable "controller_count" {
  description = "Number of Kafka controller instances (KRaft mode)"
  type        = number
  default     = 3

  validation {
    condition     = var.controller_count % 2 == 1
    error_message = "Controller count must be odd for Raft quorum (1, 3, 5, 7)"
  }
}

variable "controller_instance_type" {
  description = "EC2 instance type for controllers"
  type        = string
  default     = "t3.small"
}

variable "platform_instance_type" {
  description = "EC2 instance type for platform node"
  type        = string
  default     = "t3.small"
}

variable "spot_max_price" {
  description = "Maximum price for spot instances ($/hour)"
  type        = string
  default     = "0.015"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks for admin access (SSH, Grafana, Prometheus)"
  type        = list(string)

  validation {
    condition     = length(var.admin_cidr_blocks) > 0
    error_message = "Admin CIDR blocks must be specified for security."
  }
}

variable "public_api_cidr_blocks" {
  description = "CIDR blocks for public API access (Kafka Admin API)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}