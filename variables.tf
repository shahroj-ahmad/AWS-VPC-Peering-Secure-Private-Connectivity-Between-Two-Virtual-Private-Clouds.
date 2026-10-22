variable "aws_region" {
  description = "AWS Region to deploy all lab resources (e.g., ap-south-1 for Mumbai, us-east-1 for N. Virginia)."
  type        = string
  default     = "ap-south-1"
}

variable "student_name" {
  description = "Student name for resource tagging as required by the EWB lab brief."
  type        = string
  default     = "Student"
}

variable "my_ip" {
  description = "Your personal laptop/workstation public IPv4 address with /32 CIDR prefix (e.g. 203.0.113.25/32). NEVER set to 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/32$", var.my_ip)) && var.my_ip != "0.0.0.0/32" && var.my_ip != "0.0.0.0/0"
    error_message = "The my_ip variable must be a valid single IPv4 host address with /32 prefix (e.g., '198.51.100.15/32') and MUST NOT be 0.0.0.0/0."
  }
}

variable "key_name" {
  description = "Name of the EC2 Key Pair used across all 3 instances (ewb-bastion, ewb-app-a, ewb-app-b)."
  type        = string
  default     = "ewb-lab"
}

variable "public_key_path" {
  description = "Optional path to your local public SSH key file (e.g. ~/.ssh/ewb-lab.pub). If set, Terraform creates the AWS key pair. If left empty, Terraform expects an existing key pair named 'ewb-lab'."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for all lab hosts (t3.micro is AWS Free Tier eligible in supported regions)."
  type        = string
  default     = "t3.micro"
}

variable "enable_peering_routes" {
  description = "Control flag to create VPC peering routes in route tables. Set to false to reproduce 'Test 01 / Baseline Failure' before routing. Set to true for full peering connectivity."
  type        = bool
  default     = true
}

variable "enable_app_b_icmp_rule" {
  description = "Control flag for App-B inbound ICMP rule. Set to false to perform the 'Controlled Failure' test (Page 11) where ping from App-A fails, then back to true for recovery."
  type        = bool
  default     = true
}
