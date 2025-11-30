output "infrastructure_summary" {
  description = "Summary of infrastructure resources"
  value = {
    vpc = {
      id   = module.network.vpc_id
      cidr = module.network.vpc_cidr
    }

    subnets = {
      ids   = module.network.public_subnet_ids
      cidrs = module.network.public_subnet_cidrs
      azs   = module.network.availability_zones
    }

    brokers = {
      count        = var.broker_count
      instance_ids = module.compute.broker_instance_ids
      private_ips  = module.compute.broker_private_ips
      public_ips   = module.compute.broker_public_ips
    }

    controllers = {
      count        = var.controller_count
      instance_ids = module.compute.controller_instance_ids
      private_ips  = module.compute.controller_private_ips
      public_ips   = module.compute.controller_public_ips
    }

    platform = {
      instance_id = module.compute.platform_instance_id
      private_ip  = module.compute.platform_private_ip
      public_ip   = module.compute.platform_public_ip
    }
  }
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    brokers = [
      for idx, ip in module.compute.broker_public_ips :
      "ssh -i ~/.ssh/kafka-platform-key ubuntu@${ip}  # broker-${idx + 1}"
    ]
    controllers = [
      for idx, ip in module.compute.controller_public_ips :
      "ssh -i ~/.ssh/kafka-platform-key ubuntu@${ip}  # controller-${idx + 1}"
    ]
    platform = "ssh -i ~/.ssh/kafka-platform-key ubuntu@${module.compute.platform_public_ip}  # platform"
  }
}

output "ansible_inventory" {
  description = "Ansible inventory in JSON format"
  value = jsonencode({
    kafka_broker = {
      hosts = {
        for idx in range(var.broker_count) :
        "broker-${idx + 1}" => {
          ansible_host = module.compute.broker_public_ips[idx]
          private_ip   = module.compute.broker_private_ips[idx]
          broker_id    = idx + 1
          broker_rack  = "az-${(idx % 3) + 1}"
        }
      }
    }

    kafka_controller = {
      hosts = {
        for idx in range(var.controller_count) :
        "controller-${idx + 1}" => {
          ansible_host  = module.compute.controller_public_ips[idx]
          private_ip    = module.compute.controller_private_ips[idx]
          controller_id = idx + 1
        }
      }
    }

    platform = {
      hosts = {
        platform = {
          ansible_host = module.compute.platform_public_ip
          private_ip   = module.compute.platform_private_ip
        }
      }
    }
  })
}

output "monthly_cost_estimate" {
  description = "Estimated monthly cost (USD)"
  value = {
    compute = {
      brokers_spot     = format("$%.2f", var.broker_count * 0.0062 * 730)
      controllers_spot = format("$%.2f", var.controller_count * 0.0062 * 730)
      platform_spot    = format("$%.2f", 0.0062 * 730)
      total_compute    = format("$%.2f", (var.broker_count + var.controller_count + 1) * 0.0062 * 730)
    }
    storage = {
      brokers_ebs     = format("$%.2f", var.broker_count * 20 * 0.10)
      controllers_ebs = format("$%.2f", var.controller_count * 15 * 0.10)
      platform_ebs    = format("$%.2f", 30 * 0.10)
      total_storage   = format("$%.2f", (var.broker_count * 20 + var.controller_count * 15 + 30) * 0.10)
    }
    total = format("$%.2f",
      (var.broker_count + var.controller_count + 1) * 0.0062 * 730 +
      (var.broker_count * 20 + var.controller_count * 15 + 30) * 0.10
    )
    notes = "Spot prices are estimates. Actual cost may vary. Data transfer not included."
  }
}
