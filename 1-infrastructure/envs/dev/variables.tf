variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "kafka-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = "kafka-platform-key"
}

variable "broker_count" {
  description = "Number of Kafka brokers"
  type        = number
  default     = 4
}

variable "broker_instance_type" {
  description = "Broker instance type"
  type        = string
  default     = "t3.small"
}

variable "controller_count" {
  description = "Number of Kafka controllers"
  type        = number
  default     = 3
}

variable "controller_instance_type" {
  description = "Controller instance type"
  type        = string
  default     = "t3.small"
}

variable "platform_instance_type" {
  description = "Platform node instance type"
  type        = string
  default     = "t3.small"
}

variable "spot_max_price" {
  description = "Spot instance max price"
  type        = string
  default     = "0.015"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks for admin access (SSH, Grafana, Prometheus)"
  type        = list(string)
  default = []
}

variable "public_api_cidr_blocks" {
  description = "CIDR blocks for public API access (Kafka Admin API)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "spot_price_per_hour" {
  description = "Estimated spot price per hour (USD)"
  type        = number
  default     = 0.0062
}

variable "ebs_price_per_gb" {
  description = "EBS gp3 price per GB per month (USD)"
  type        = number
  default     = 0.10
}

variable "hours_per_month" {
  description = "Hours in a month for cost calculation"
  type        = number
  default     = 730
}

variable "broker_ebs_size" {
  description = "EBS volume size for brokers (GB)"
  type        = number
  default     = 20
}

variable "controller_ebs_size" {
  description = "EBS volume size for controllers (GB)"
  type        = number
  default     = 15
}

variable "platform_ebs_size" {
  description = "EBS volume size for platform (GB)"
  type        = number
  default     = 30
}