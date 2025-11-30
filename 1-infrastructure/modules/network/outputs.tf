output "vpc_id" {
  description = "ID of the VPC"
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids"{
  description = "List of public subnet IDs"
  value = [for subnet in aws_subnet.public : subnet.id]
}

output "public_subnet_cidrs"{
  description = "List of public subnet CIDR blocks"
  value = [for subnet in aws_subnet.public : subnet.cidr_block]
}

output "availability_zones"{
  description = "List of availability zones used"
  value = [for subnet in aws_subnet.public : subnet.availability_zone]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value = aws_internet_gateway.main.id
}

