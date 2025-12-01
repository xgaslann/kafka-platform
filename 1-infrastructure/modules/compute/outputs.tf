output "broker_instance_ids" {
  description = "List of broker instance IDs"
  value       = [for broker in aws_instance.kafka_broker : broker.id]
}

output "broker_private_ips" {
  description = "List of broker private IP addresses"
  value       = [for broker in aws_instance.kafka_broker : broker.private_ip]
}

output "broker_public_ips" {
  description = "List of broker public IP addresses"
  value       = [for broker in aws_instance.kafka_broker : broker.public_ip]
}

output "controller_instance_ids" {
  description = "List of controller instance IDs"
  value       = [for controller in aws_instance.kafka_controller : controller.id]
}

output "controller_private_ips" {
  description = "List of controller private IP addresses"
  value       = [for controller in aws_instance.kafka_controller : controller.private_ip]
}

output "controller_public_ips" {
  description = "List of controller public IP addresses"
  value       = [for controller in aws_instance.kafka_controller : controller.public_ip]
}

output "platform_instance_id" {
  description = "Platform node instance ID"
  value       = aws_instance.platform.id
}

output "platform_private_ip" {
  description = "Platform node private IP"
  value       = aws_instance.platform.private_ip
}

output "platform_public_ip" {
  description = "Platform node public IP"
  value       = aws_instance.platform.public_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.kafka_cluster.id
}