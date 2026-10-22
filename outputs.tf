output "vpc_a_id" {
  description = "ID of VPC A (10.10.0.0/16)"
  value       = aws_vpc.vpc_a.id
}

output "vpc_b_id" {
  description = "ID of VPC B (10.20.0.0/16)"
  value       = aws_vpc.vpc_b.id
}

output "peering_connection_id" {
  description = "ID of the VPC Peering Connection (pcx-xxxxxx)"
  value       = aws_vpc_peering_connection.peer.id
}

output "peering_connection_status" {
  description = "Status of the VPC Peering Connection"
  value       = aws_vpc_peering_connection.peer.accept_status
}

output "internet_gateway_id" {
  description = "ID of Internet Gateway attached to VPC A"
  value       = aws_internet_gateway.igw_a.id
}

output "subnet_a_public_id" {
  description = "ID of Public Subnet A (10.10.1.0/24)"
  value       = aws_subnet.a_public.id
}

output "subnet_a_private_id" {
  description = "ID of Private Subnet A (10.10.2.0/24)"
  value       = aws_subnet.a_private.id
}

output "subnet_b_private_id" {
  description = "ID of Private Subnet B (10.20.1.0/24)"
  value       = aws_subnet.b_private.id
}

output "bastion_instance_id" {
  description = "EC2 Instance ID of Bastion Host"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address of Bastion Host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IPv4 address of Bastion Host (10.10.1.10)"
  value       = aws_instance.bastion.private_ip
}

output "app_a_instance_id" {
  description = "EC2 Instance ID of App-A"
  value       = aws_instance.app_a.id
}

output "app_a_private_ip" {
  description = "Private IPv4 address of App-A (10.10.2.10)"
  value       = aws_instance.app_a.private_ip
}

output "app_b_instance_id" {
  description = "EC2 Instance ID of App-B"
  value       = aws_instance.app_b.id
}

output "app_b_private_ip" {
  description = "Private IPv4 address of App-B (10.20.1.10)"
  value       = aws_instance.app_b.private_ip
}

output "ssh_config_snippet" {
  description = "Copy and paste this snippet directly into your local ~/.ssh/config"
  value       = <<-EOT
    # ==========================================================
    # EWB AWS VPC Peering Lab - SSH Config
    # Place this inside ~/.ssh/config on your MacBook
    # ==========================================================
    Host ewb-bastion
        HostName ${aws_instance.bastion.public_ip}
        User ec2-user
        IdentityFile ~/.ssh/ewb-lab.pem
        IdentitiesOnly yes

    Host ewb-app-a
        HostName ${aws_instance.app_a.private_ip}
        User ec2-user
        IdentityFile ~/.ssh/ewb-lab.pem
        IdentitiesOnly yes
        ProxyJump ewb-bastion

    Host ewb-app-b
        HostName ${aws_instance.app_b.private_ip}
        User ec2-user
        IdentityFile ~/.ssh/ewb-lab.pem
        IdentitiesOnly yes
        ProxyJump ewb-bastion
  EOT
}
