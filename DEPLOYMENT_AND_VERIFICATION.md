# Deployment and Verification Guide

This guide walks you through every phase of deploying, validating, testing, and cleaning up the **AWS VPC Peering Lab** on your macOS machine according to the official EWB Course Project specifications.

---

## 1. Prerequisites and macOS Environment Setup

### 1.1 Install Prerequisites (via Homebrew)
If you do not already have Terraform and the AWS CLI installed, open your Terminal on macOS and run:
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Terraform and AWS CLI
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install awscli
```

### 1.2 Configure AWS Credentials Securely on macOS
AWS credentials should **never** be hardcoded in `.tf` files or committed to Git. Configure your credentials securely using AWS CLI:

```bash
aws configure
```
You will be prompted for:
- **AWS Access Key ID**: Your IAM User Access Key
- **AWS Secret Access Key**: Your IAM User Secret Key
- **Default region name**: `ap-south-1` (Mumbai) or your chosen region
- **Default output format**: `json`

This creates `~/.aws/credentials` and `~/.aws/config`. Protect these files with strict POSIX permissions:
```bash
chmod 600 ~/.aws/credentials ~/.aws/config
```

Verify your authentication:
```bash
aws sts get-caller-identity
```

### 1.3 Create or Prepare the EC2 Key Pair (`ewb-lab`)
The project requires an RSA key pair named `ewb-lab`.

**Option A (Using AWS Console):**
1. Navigate to **EC2 Console > Network & Security > Key Pairs**.
2. Click **Create Key Pair**.
3. Name: `ewb-lab`, Key pair type: `RSA`, Private key file format: `.pem`.
4. Download `ewb-lab.pem` and move it to `~/.ssh/`:
   ```bash
   mkdir -p ~/.ssh
   mv ~/Downloads/ewb-lab.pem ~/.ssh/ewb-lab.pem
   chmod 400 ~/.ssh/ewb-lab.pem
   ```

**Option B (Generate locally and let Terraform upload it):**
```bash
mkdir -p ~/.ssh
ssh-keygen -t rsa -b 2048 -f ~/.ssh/ewb-lab -N ""
mv ~/.ssh/ewb-lab ~/.ssh/ewb-lab.pem
chmod 400 ~/.ssh/ewb-lab.pem
chmod 644 ~/.ssh/ewb-lab.pub
```
*(If using Option B, set `public_key_path = "~/.ssh/ewb-lab.pub"` in `terraform.tfvars`)*.

---

## 2. Terraform Configuration Setup

### 2.1 Find Your Current Public IP Address
To follow the strict security requirements and never expose SSH or ICMP to `0.0.0.0/0`, obtain your exact workstation IP:
```bash
curl -s https://checkip.amazonaws.com
```
*Example Output: `203.0.113.45`*

### 2.2 Create `terraform.tfvars`
Copy the example file and edit it:
```bash
cp terraform.tfvars.example terraform.tfvars
```
Edit `terraform.tfvars`:
```hcl
aws_region   = "ap-south-1"
student_name = "YourName"
my_ip        = "203.0.113.45/32"    # Replace with your actual IP from above + /32
key_name     = "ewb-lab"
```

---

## 3. Terraform Validation and Execution Workflow

### Step 1: Initialize Working Directory
Downloads the AWS provider plugins:
```bash
terraform init
```

### Step 2: Format and Validate
Ensures code is canonical and syntactically correct:
```bash
terraform fmt -check
terraform validate
```
*Expected Output: `Success! The configuration is valid.`*

### Step 3: Generate and Review the Execution Plan
```bash
terraform plan -out=tfplan
```
**Safety Review Checklist:**
- Inspect the plan summary: It should propose adding resources (VPCs, Subnets, Route Tables, Peering Connection, Security Groups, and EC2 instances).
- Confirm CIDR blocks:
  - VPC A: `10.10.0.0/16`
  - Subnet A Public: `10.10.1.0/24`
  - Subnet A Private: `10.10.2.0/24`
  - VPC B: `10.20.0.0/16`
  - Subnet B Private: `10.20.1.0/24`
- Confirm Security Group ingress rules:
  - Bastion: TCP 22 strictly from your `/32`.
  - App-A: TCP 22 from `10.10.1.10/32`, ICMP Echo from `10.20.1.10/32`.
  - App-B: TCP 22 from `10.10.1.10/32`, ICMP Echo from `10.10.2.10/32`.

### Step 4: Apply the Plan (Manual Confirmation)
```bash
terraform apply tfplan
```
Wait 2 to 3 minutes until deployment completes. Terraform will print the outputs including resource IDs, IP addresses, and the SSH config snippet.

---

## 4. SSH ProxyJump Configuration on macOS

Terraform outputs a ready-to-use snippet for `~/.ssh/config`. Append or create this in `~/.ssh/config`:

```ssh-config
Host ewb-bastion
    HostName <BASTION_PUBLIC_IP>
    User ec2-user
    IdentityFile ~/.ssh/ewb-lab.pem
    IdentitiesOnly yes

Host ewb-app-a
    HostName 10.10.2.10
    User ec2-user
    IdentityFile ~/.ssh/ewb-lab.pem
    IdentitiesOnly yes
    ProxyJump ewb-bastion

Host ewb-app-b
    HostName 10.20.1.10
    User ec2-user
    IdentityFile ~/.ssh/ewb-lab.pem
    IdentitiesOnly yes
    ProxyJump ewb-bastion
```

Set correct permissions on `~/.ssh/config`:
```bash
chmod 600 ~/.ssh/config
```

---

## 5. Verification, Testing, and Evidence Collection

Follow the exact testing order specified in the EWB project workbook (Pages 8, 10, 11).

### Checkpoint 01 & 02: Architecture and Isolation Audit
Run the following from your laptop to verify isolation:
```bash
# Confirm App-A has NO public IP
aws ec2 describe-instances --filters "Name=tag:Name,Values=ewb-app-a" \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,PublicIpAddress]" --output table

# Confirm App-B has NO public IP
aws ec2 describe-instances --filters "Name=tag:Name,Values=ewb-app-b" \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,PublicIpAddress]" --output table
```
*Expected: The `PublicIpAddress` column is `None` for both private instances.*

---

### Test 01: Baseline Failure (Before Peering Routes)
*Acceptance Criteria: Without peering routes, private instances cannot communicate.*

If you wish to capture the baseline failure before routes are added:
1. Temporarily set `enable_peering_routes = false` in `terraform.tfvars`.
2. Run `terraform apply -auto-approve`.
3. SSH into App-A via ProxyJump:
   ```bash
   ssh ewb-app-a
   ```
4. Run baseline ping to App-B:
   ```bash
   hostname -I
   ping -c 4 10.20.1.10
   ```
   *Expected Output: `100% packet loss` (no replies).*
5. Take a screenshot for your report.
6. Type `exit` to return to your laptop.
7. Set `enable_peering_routes = true` in `terraform.tfvars` and run `terraform apply -auto-approve`.

---

### Test 02: Forward Path Connectivity (App-A -> App-B)
1. SSH into App-A from your laptop:
   ```bash
   ssh ewb-app-a
   ```
2. Identify host and ping App-B:
   ```bash
   hostname
   hostname -I
   ping -c 4 10.20.1.10
   ```
3. *Expected Output:*
   ```text
   PING 10.20.1.10 (10.20.1.10) 56(84) bytes of data.
   64 bytes from 10.20.1.10: icmp_seq=1 ttl=64 time=0.982 ms
   64 bytes from 10.20.1.10: icmp_seq=2 ttl=64 time=0.821 ms
   64 bytes from 10.20.1.10: icmp_seq=3 ttl=64 time=0.845 ms
   64 bytes from 10.20.1.10: icmp_seq=4 ttl=64 time=0.812 ms

   --- 10.20.1.10 ping statistics ---
   4 packets transmitted, 4 received, 0% packet loss
   ```
4. Exit back to your laptop:
   ```bash
   exit
   ```

---

### Test 03: Reverse Path Connectivity (App-B -> App-A)
1. SSH into App-B from your laptop via ProxyJump:
   ```bash
   ssh ewb-app-b
   ```
2. Identify host and ping App-A:
   ```bash
   hostname
   hostname -I
   ping -c 4 10.10.2.10
   ```
3. *Expected Output:*
   ```text
   4 packets transmitted, 4 received, 0% packet loss
   ```
4. Exit back to your laptop:
   ```bash
   exit
   ```

---

### Test 04: Private SSH Access to App-B via Bastion
Connect directly from your laptop:
```bash
ssh ewb-app-b
```
*Expected Result: You receive an interactive shell prompt on `[ec2-user@ip-10-20-1-10 ~]$` without copying private keys to the bastion.*
Type `exit`.

---

### Test 05: Controlled ICMP Failure & Recovery Test
*(Workbook Page 11 Requirement: Prove that the security group rule is actively protecting the workload)*

#### Step 1: Trigger Controlled Failure
Temporarily disable the App-B ICMP rule:
- **Via Terraform:** In `terraform.tfvars`, set `enable_app_b_icmp_rule = false` and run `terraform apply -auto-approve`.
- *(Or via AWS Console): In EC2 > Security Groups > `ewb-sg-app-b` > Edit Inbound Rules > Delete the ICMP Echo rule.*

Now SSH into App-A and ping App-B:
```bash
ssh ewb-app-a
ping -c 4 -W 2 10.20.1.10
```
*Expected Result:*
```text
--- 10.20.1.10 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss
```
Capture screenshot of this failure! Notice SSH to App-B still works because TCP 22 was untouched.
Type `exit`.

#### Step 2: Trigger Recovery
Restore the ICMP rule:
- **Via Terraform:** In `terraform.tfvars`, set `enable_app_b_icmp_rule = true` and run `terraform apply -auto-approve`.
- *(Or via AWS Console): Re-add Custom ICMP IPv4 Echo Request (Port: N/A, Source: `10.10.2.10/32`).*

SSH into App-A and re-test:
```bash
ssh ewb-app-a
ping -c 4 10.20.1.10
```
*Expected Result: Replies resume immediately with 0% packet loss.*
Capture screenshot of the recovery!

---

## 6. Troubleshooting Guide

| Symptom | Probable Cause | Diagnostic Command & Fix |
| :--- | :--- | :--- |
| **Bastion SSH times out** | Security Group does not match current public IP or IGW route missing | Check IP with `curl -s ifconfig.me`. Update `my_ip` in `terraform.tfvars`. Verify route `0.0.0.0/0 -> ewb-igw-a` in `ewb-rt-a-public`. |
| **App-A SSH fails** | Inbound rule not matching Bastion private IP | Check `ewb-sg-app-a` allows TCP 22 from `10.10.1.10/32`. Verify bastion is up. |
| **App-B SSH fails** | Missing peering route in Bastion public subnet or VPC B | Bastion route table (`ewb-rt-a-public`) MUST have `10.20.0.0/16 -> pcx-ID`. VPC B route table (`ewb-rt-b-private`) MUST have `10.10.0.0/16 -> pcx-ID`. |
| **Ping fails after peering accepted** | Security Group ICMP rule missing or asymmetric routing | Verify Security Group has ICMP Echo Request (Type 8, Code 0). Both route tables must have cross-VPC CIDRs pointing to `pcx-xxxxxx`. |
| **Permission denied (publickey)** | Wrong key path or bad permissions | Ensure key is `chmod 400 ~/.ssh/ewb-lab.pem`. User must be `ec2-user` for Amazon Linux 2023. |
| **Peering creation fails** | Overlapping CIDRs | VPC A (`10.10.0.0/16`) and VPC B (`10.20.0.0/16`) must have no overlapping IP blocks. |

---

## 7. Cost Estimation and Billing Safety

| Resource | Quantity | Free Tier / Pricing Rate | Expected Cost for Lab (2 Hours) |
| :--- | :--- | :--- | :--- |
| **t3.micro EC2** | 3 instances | Free Tier eligible (750 hrs/month). Otherwise ~$0.0104/hr each | $0.00 – $0.06 |
| **Public IPv4 Address** | 1 (Bastion) | AWS charge: $0.005/hr | ~$0.01 |
| **EBS Storage** | 3x 8GB gp3 | 30GB/month Free Tier eligible | $0.00 |
| **VPC Peering Connection** | 1 connection | Free to create | $0.00 |
| **Peering Data Transfer** | < 10 MB | $0.01 per GB in same region | < $0.001 |
| **NAT Gateway** | 0 | **NOT USED** (Lab avoids expensive NAT Gateways) | $0.00 |

*Estimated Total Cost: Under $0.10 USD (Free if within Free Tier allowance).*

---

## 8. Complete Teardown and Cleanup Procedure

To avoid unexpected AWS charges, clean up immediately after capturing your test evidence:

### Step 1: Run Terraform Destroy
From your project directory:
```bash
terraform destroy
```
Type `yes` when prompted to confirm.

### Step 2: Verify in AWS Console
1. **EC2 Instances**: Confirm `ewb-bastion`, `ewb-app-a`, and `ewb-app-b` are in `Terminated` state.
2. **Elastic IPs / Public IPs**: Confirm no lingering Elastic IPs.
3. **EBS Volumes**: Verify the three 8GB root volumes were deleted with instance termination.
4. **VPC Peering Connections**: Confirm `ewb-a-b-peer` is deleted.
5. **VPCs**: Confirm `ewb-vpc-a` and `ewb-vpc-b` are removed.
