data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch the official Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Optional: Create AWS Key Pair if public_key_path is provided
resource "aws_key_pair" "ewb_lab" {
  count      = var.public_key_path != "" ? 1 : 0
  key_name   = var.key_name
  public_key = file(var.public_key_path)

  tags = {
    Name = var.key_name
  }
}

locals {
  ssh_key_name      = var.public_key_path != "" ? aws_key_pair.ewb_lab[0].key_name : var.key_name
  availability_zone = data.aws_availability_zones.available.names[0]
}

# ==============================================================================
# 1. VPC A & SUBNETS (10.10.0.0/16)
# ==============================================================================

resource "aws_vpc" "vpc_a" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ewb-vpc-a"
  }
}

resource "aws_subnet" "a_public" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "ewb-a-public"
  }
}

resource "aws_subnet" "a_private" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "ewb-a-private"
  }
}

# Internet Gateway for VPC A only
resource "aws_internet_gateway" "igw_a" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-igw-a"
  }
}

# ==============================================================================
# 2. VPC B & SUBNET (10.20.0.0/16) - NO INTERNET GATEWAY
# ==============================================================================

resource "aws_vpc" "vpc_b" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ewb-vpc-b"
  }
}

resource "aws_subnet" "b_private" {
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "ewb-b-private"
  }
}

# ==============================================================================
# 3. VPC PEERING CONNECTION (Requester: VPC A -> Accepter: VPC B)
# ==============================================================================

resource "aws_vpc_peering_connection" "peer" {
  vpc_id      = aws_vpc.vpc_a.id
  peer_vpc_id = aws_vpc.vpc_b.id
  auto_accept = true

  tags = {
    Name = "ewb-a-b-peer"
  }
}

# ==============================================================================
# 4. ROUTE TABLES AND ASSOCIATIONS
# ==============================================================================

# 4A. VPC A - Public Route Table
resource "aws_route_table" "rt_a_public" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-rt-a-public"
  }
}

# Subnet association for Public Subnet A
resource "aws_route_table_association" "a_public" {
  subnet_id      = aws_subnet.a_public.id
  route_table_id = aws_route_table.rt_a_public.id
}

# Internet Default Route (0.0.0.0/0 -> IGW A)
resource "aws_route" "a_public_internet" {
  route_table_id         = aws_route_table.rt_a_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_a.id
}

# Peering Route: Bastion needs to reach VPC B (10.20.0.0/16) for ProxyJump SSH to App-B
resource "aws_route" "a_public_to_vpc_b" {
  count                     = var.enable_peering_routes ? 1 : 0
  route_table_id            = aws_route_table.rt_a_public.id
  destination_cidr_block    = "10.20.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

# 4B. VPC A - Private Route Table
resource "aws_route_table" "rt_a_private" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-rt-a-private"
  }
}

# Subnet association for Private Subnet A
resource "aws_route_table_association" "a_private" {
  subnet_id      = aws_subnet.a_private.id
  route_table_id = aws_route_table.rt_a_private.id
}

# Peering Route: App-A to VPC B (10.20.0.0/16 -> PCX)
resource "aws_route" "a_private_to_vpc_b" {
  count                     = var.enable_peering_routes ? 1 : 0
  route_table_id            = aws_route_table.rt_a_private.id
  destination_cidr_block    = "10.20.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

# 4C. VPC B - Private Route Table
resource "aws_route_table" "rt_b_private" {
  vpc_id = aws_vpc.vpc_b.id

  tags = {
    Name = "ewb-rt-b-private"
  }
}

# Subnet association for Private Subnet B
resource "aws_route_table_association" "b_private" {
  subnet_id      = aws_subnet.b_private.id
  route_table_id = aws_route_table.rt_b_private.id
}

# Return Peering Route: VPC B return path to VPC A (10.10.0.0/16 -> PCX)
resource "aws_route" "b_private_to_vpc_a" {
  count                     = var.enable_peering_routes ? 1 : 0
  route_table_id            = aws_route_table.rt_b_private.id
  destination_cidr_block    = "10.10.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

# ==============================================================================
# 5. SECURITY GROUPS (Strict Least-Privilege Rules)
# ==============================================================================

# 5A. Bastion Host Security Group (VPC A)
resource "aws_security_group" "sg_bastion" {
  name        = "ewb-sg-bastion"
  description = "Security Group for Bastion Host in VPC A"
  vpc_id      = aws_vpc.vpc_a.id

  # Inbound: SSH (Port 22) restricted strictly to student's workstation public IP /32
  ingress {
    description = "SSH from authorized student workstation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Outbound: Stateful allow all egress
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-bastion"
  }
}

# 5B. App-A Security Group (VPC A)
resource "aws_security_group" "sg_app_a" {
  name        = "ewb-sg-app-a"
  description = "Security Group for App-A in VPC A"
  vpc_id      = aws_vpc.vpc_a.id

  # Inbound: SSH (Port 22) restricted strictly to Bastion private IP (10.10.1.10/32)
  ingress {
    description = "SSH from Bastion private IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.1.10/32"]
  }

  # Inbound: Custom ICMP IPv4 Echo Request (Type 8, Code 0) from App-B (10.20.1.10/32)
  ingress {
    description = "ICMP Echo Request from App-B private IP"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["10.20.1.10/32"]
  }

  # Outbound: Stateful allow all egress
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-app-a"
  }
}

# 5C. App-B Security Group (VPC B)
resource "aws_security_group" "sg_app_b" {
  name        = "ewb-sg-app-b"
  description = "Security Group for App-B in VPC B"
  vpc_id      = aws_vpc.vpc_b.id

  # Inbound: SSH (Port 22) restricted strictly to Bastion private IP (10.10.1.10/32)
  ingress {
    description = "SSH from Bastion private IP via VPC Peering"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.1.10/32"]
  }

  # Outbound: Stateful allow all egress
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-app-b"
  }
}

# App-B Inbound ICMP Echo Request rule (Configurable for Controlled Failure Test)
resource "aws_security_group_rule" "app_b_icmp" {
  count             = var.enable_app_b_icmp_rule ? 1 : 0
  type              = "ingress"
  description       = "ICMP Echo Request from App-A private IP (Testable for controlled failure)"
  from_port         = 8
  to_port           = 0
  protocol          = "icmp"
  cidr_blocks       = ["10.10.2.10/32"]
  security_group_id = aws_security_group.sg_app_b.id
}

# ==============================================================================
# 6. EC2 INSTANCES (Exact Private IP Allocations)
# ==============================================================================

# 6A. Bastion Host (VPC A / Public Subnet / 10.10.1.10 / Public IP Enabled)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.a_public.id
  private_ip                  = "10.10.1.10"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg_bastion.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "ewb-bastion"
  }
}

# 6B. App-A Workload (VPC A / Private Subnet / 10.10.2.10 / No Public IP)
resource "aws_instance" "app_a" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.a_private.id
  private_ip                  = "10.10.2.10"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.sg_app_a.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "ewb-app-a"
  }
}

# 6C. App-B Workload (VPC B / Private Subnet / 10.20.1.10 / No Public IP)
resource "aws_instance" "app_b" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.b_private.id
  private_ip                  = "10.20.1.10"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.sg_app_b.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "ewb-app-b"
  }
}
