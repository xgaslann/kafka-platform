variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  validation {
    condition = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type = string
  default = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (like 10.0.0.0/16)"
  type = string
  default = "10.0.0.0/16"
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for subnet distribution"
  type = list(string)
  default = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  validation {
    condition = length(var.availability_zones) >= 2
    error_message = "At least two availability zones required for HA"
  }
}
