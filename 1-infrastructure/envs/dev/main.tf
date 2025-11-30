terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

data "http" "my_ip" {
  url = "https://api.ipify.org?format=text"
}

locals {
  my_ip = "${chomp(data.http.my_ip.response_body)}/32"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Görkem Aslan"
      CostCenter  = "Engineering"
    }
  }
}

module "network" {
  source             = "../../modules/network"
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "compute" {
  source                   = "../../modules/compute"
  project_name             = var.project_name
  environment              = var.environment
  vpc_id                   = module.network.vpc_id
  vpc_cidr                 = module.network.vpc_cidr
  public_subnet_ids        = module.network.public_subnet_ids
  public_subnet_cidrs      = module.network.public_subnet_cidrs
  key_name                 = var.key_name
  broker_count             = var.broker_count
  broker_instance_type     = var.broker_instance_type
  controller_count         = var.controller_count
  controller_instance_type = var.controller_instance_type
  platform_instance_type   = var.platform_instance_type
  spot_max_price           = var.spot_max_price

  admin_cidr_blocks      = coalescelist(var.admin_cidr_blocks, [local.my_ip])
  public_api_cidr_blocks = var.public_api_cidr_blocks
}