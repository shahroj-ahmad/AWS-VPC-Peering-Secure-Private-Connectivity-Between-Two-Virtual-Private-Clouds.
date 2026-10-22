# COLLEGE ASSIGNMENT PROJECT REPORT

**Course / Lab**: AWS Solutions Architect Associate / Cloud Networking  
**Project Title**: AWS VPC Peering — Secure Private Connectivity Between Two Virtual Private Clouds  
**Document Name**: `[YourName]_EWB_VPC_Peering.pdf` (Export this template to PDF upon completion)  

---

## STUDENT INFORMATION
- **Student Name**: `___________________________`
- **Roll Number / Student ID**: `___________________________`
- **Batch / Section**: `___________________________`
- **Academic Institution**: `___________________________`
- **AWS Region Used**: `ap-south-1` (Mumbai)
- **Date of Completion**: `___________________________`

---

## 1. PROJECT OBJECTIVE & EXECUTIVE SUMMARY
The objective of this engineering project is to design, deploy, and rigorously validate secure, private cross-VPC networking between two decoupled Virtual Private Clouds (**VPC A: 10.10.0.0/16** and **VPC B: 10.20.0.0/16**) using **AWS VPC Peering**, **Custom Route Tables**, **Strict Least-Privilege Security Groups**, and **SSH ProxyJump** via a public bastion host.

Both application workloads (**App-A: 10.10.2.10** and **App-B: 10.20.1.10**) remain completely isolated with zero public IPv4 addresses and no internet egress. Connectivity is established purely over the AWS private global network backbone, avoiding internet exposure and eliminating the recurring cost and architectural overhead of NAT Gateways or complex VPN tunnels.

---

## 2. ARCHITECTURE DIAGRAM & TOPOLOGY

```
                                +-----------------------------+
                                |   Student Laptop (macOS)    |
                                |     [~/.ssh/config]         |
                                +--------------+--------------+
                                               |
                                     SSH Port 22 (my_ip/32)
                                               |
                                               v
                                +-----------------------------+
                                |  Internet Gateway (VPC A)   |
                                |         ewb-igw-a           |
                                +--------------+--------------+
                                               |
===============================================|===============================================
VPC A: ewb-vpc-a (10.10.0.0/16)                |
                                               v
  +------------------------------------------------------------------------------------------+
  | Public Subnet: ewb-a-public (10.10.1.0/24) | Route Table: ewb-rt-a-public                |
  |                                                                                          |
  |  [ ewb-bastion ]                                                                         |
  |  - Private IP: 10.10.1.10                                                                |
  |  - Public IP:  Auto-assigned                                                             |
  |  - Security Group: ewb-sg-bastion (TCP 22 from Student /32)                              |
  +------------------------------------------------------------------------------------------+
            |                                           |
    ProxyJump SSH (Local)                       ProxyJump SSH (Cross-VPC)
            |                                           |
            v                                           |
  +-------------------------------------------+         |
  | Private Subnet: ewb-a-private             |         |
  | (10.10.2.0/24)                            |         |
  |                                           |         |
  |  [ ewb-app-a ]                            |         |
  |  - Private IP: 10.10.2.10                 |         |
  |  - Public IP:  NONE                       |         |
  |  - SG: ewb-sg-app-a                       |         |
  |    • TCP 22 from 10.10.1.10/32            |         |
  |    • ICMP Echo from 10.20.1.10/32         |         |
  +-------------------------------------------+         |
            ^                                           |
            |            =========================      |
            |            VPC PEERING CONNECTION         |
            +----------< [ ewb-a-b-peer (pcx) ] >-------+
                         =========================      |
========================================================|======================================
VPC B: ewb-vpc-b (10.20.0.0/16) - NO IGW / NO NAT       |
                                                        v
  +------------------------------------------------------------------------------------------+
  | Private Subnet: ewb-b-private (10.20.1.0/24) | Route Table: ewb-rt-b-private             |
  |                                                                                          |
  |  [ ewb-app-b ]                                                                           |
  |  - Private IP: 10.20.1.10                                                                |
  |  - Public IP:  NONE                                                                      |
  |  - Security Group: ewb-sg-app-b                                                          |
  |    • TCP 22 from 10.10.1.10/32 (via Bastion)                                             |
  |    • ICMP Echo from 10.10.2.10/32 (via Peering)                                          |
  +------------------------------------------------------------------------------------------+
```

---

## 3. RESOURCE INVENTORY & ADDRESSING PLAN

*(Fill in with your real AWS Resource IDs generated by `terraform output`)*

| Resource Name | Logical AWS Resource | Subnet / VPC | Assigned IPv4 / CIDR | Actual AWS Resource ID |
| :--- | :--- | :--- | :--- | :--- |
| **ewb-vpc-a** | AWS VPC | VPC A | `10.10.0.0/16` | `vpc-____________________` |
| **ewb-a-public** | Public Subnet | VPC A | `10.10.1.0/24` | `subnet-_________________` |
| **ewb-a-private** | Private Subnet | VPC A | `10.10.2.0/24` | `subnet-_________________` |
| **ewb-vpc-b** | AWS VPC | VPC B | `10.20.0.0/16` | `vpc-____________________` |
| **ewb-b-private** | Private Subnet | VPC B | `10.20.1.0/24` | `subnet-_________________` |
| **ewb-igw-a** | Internet Gateway | VPC A | N/A | `igw-____________________` |
| **ewb-a-b-peer** | VPC Peering Connection | Cross-VPC | Status: Active | `pcx-____________________` |
| **ewb-bastion** | EC2 (t3.micro) | ewb-a-public | `10.10.1.10` / Public: `______` | `i-______________________` |
| **ewb-app-a** | EC2 (t3.micro) | ewb-a-private | `10.10.2.10` / Public: None | `i-______________________` |
| **ewb-app-b** | EC2 (t3.micro) | ewb-b-private | `10.20.1.10` / Public: None | `i-______________________` |

---

## 4. ROUTE TABLES AND SECURITY SPECIFICATIONS

### 4.1 Route Table Configurations

#### A. Public Route Table (`ewb-rt-a-public`) — Associated with `ewb-a-public`
| Destination | Target | Purpose |
| :--- | :--- | :--- |
| `10.10.0.0/16` | `local` | Default local route within VPC A (Bastion to App-A) |
| `0.0.0.0/0` | `ewb-igw-a` | Inbound SSH from student laptop and internet access |
| `10.20.0.0/16` | `ewb-a-b-peer` (pcx) | Allows Bastion to reach App-B for ProxyJump SSH |

#### B. Private Route Table A (`ewb-rt-a-private`) — Associated with `ewb-a-private`
| Destination | Target | Purpose |
| :--- | :--- | :--- |
| `10.10.0.0/16` | `local` | Default local route within VPC A |
| `10.20.0.0/16` | `ewb-a-b-peer` (pcx) | Forward path from App-A to VPC B workloads |

#### C. Private Route Table B (`ewb-rt-b-private`) — Associated with `ewb-b-private`
| Destination | Target | Purpose |
| :--- | :--- | :--- |
| `10.20.0.0/16` | `local` | Default local route within VPC B |
| `10.10.0.0/16` | `ewb-a-b-peer` (pcx) | Return path to VPC A (responses to App-A and Bastion) |

### 4.2 Security Group Rules

| Security Group | Inbound Protocol | Port / Type | Source CIDR | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **ewb-sg-bastion** | TCP | 22 | `[Your_Public_IP]/32` | Whitelisted personal IP only. Never 0.0.0.0/0. |
| **ewb-sg-app-a** | TCP | 22 | `10.10.1.10/32` | Only the Bastion host can initiate SSH sessions. |
| **ewb-sg-app-a** | Custom ICMP (IPv4) | Echo Request (Type 8, Code 0) | `10.20.1.10/32` | Only App-B can send ping requests to App-A. |
| **ewb-sg-app-b** | TCP | 22 | `10.10.1.10/32` | Only the Bastion host can initiate SSH sessions over peering. |
| **ewb-sg-app-b** | Custom ICMP (IPv4) | Echo Request (Type 8, Code 0) | `10.10.2.10/32` | Only App-A can send ping requests to App-B. |

---

## 5. EXPERIMENTAL RESULTS AND EVIDENCE CHECKLIST

*(Attach the required terminal screenshots and fill in your actual execution results. Do not fabricate results; record your own outputs).*

### Screenshot Checklist & Test Results Matrix

| Test ID | Test Description | Command Executed | Expected Criteria | Actual Output Recorded | Pass/Fail | Screenshot Included? |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Test 01** | Baseline Failure (Before Routes) | `ping -c 4 10.20.1.10` on App-A | 0 replies, 100% loss | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 02** | Forward Path Ping | `ping -c 4 10.20.1.10` on App-A | 4 replies, 0% loss | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 03** | Reverse Path Ping | `ping -c 4 10.10.2.10` on App-B | 4 replies, 0% loss | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 04** | Private SSH via ProxyJump | `ssh ewb-app-b` on Laptop | Shell prompt on App-B | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 05** | Host Isolation Verification | `hostname -I` on App-A & App-B | Only 10.x.x.x, no public IP | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 06A**| Controlled ICMP Failure | `ping -c 4 10.20.1.10` (Rule Removed) | 100% packet loss | `___________________` | `[  ]` | `[  ]` Yes |
| **Test 06B**| Controlled ICMP Recovery | `ping -c 4 10.20.1.10` (Rule Restored) | 4 replies, 0% loss | `___________________` | `[  ]` | `[  ]` Yes |

### 5.1 Analysis of Controlled Failure Test
**Observation**: When the inbound rule permitting ICMP Echo requests from `10.10.2.10/32` was temporarily dropped from `ewb-sg-app-b`, the forward ping from App-A immediately experienced 100% packet loss. Crucially, SSH access to App-B through the Bastion host remained operational because TCP port 22 is governed by a distinct security group rule that was left intact. Upon restoring the ICMP rule, bidirectional ping resumed instantly without needing instance reboots or routing changes.

---

## 6. VIVA VOCE DEFENSE & TECHNICAL QUESTIONS

Be prepared to answer these core architectural questions during the lab assessment:

### Q1: Why is a return route required in VPC B's route table?
**Answer**: IP routing is strictly stateless and directional at the network layer. When App-A (`10.10.2.10`) transmits an ICMP Echo Request or TCP SYN packet to App-B (`10.20.1.10`), VPC A routes the packet across `pcx-xxxxxx`. When App-B crafts the Echo Reply or TCP SYN-ACK response, the destination IP is `10.10.2.10`. Unless VPC B's route table explicitly contains a route matching `10.10.0.0/16` targeting `pcx-xxxxxx`, the kernel has no path for the return packet and drops it. A peering link cannot function with one-way routing.

### Q2: Why does the public subnet in VPC A need a peering route to VPC B?
**Answer**: When an SSH session is established to App-B using OpenSSH ProxyJump, the student's laptop connects to the Bastion host, and the Bastion daemon opens a secondary TCP connection directly from its private IP (`10.10.1.10`) to App-B (`10.20.1.10`). Because the Bastion resides in `ewb-a-public`, packets to `10.20.1.10` evaluate the route table `ewb-rt-a-public`. By the Longest Prefix Match rule, the more specific route `10.20.0.0/16 -> pcx` takes precedence over the internet default route `0.0.0.0/0 -> igw`, allowing the Bastion to reach App-B.

### Q3: Why is the source IP received by App-B for SSH the Bastion's private IP rather than the student's public IP?
**Answer**: ProxyJump operates by port forwarding at Layer 7 / Layer 4. The initial SSH session terminates at the Bastion. The Bastion initiates an independent outbound SSH client session to App-B's private IP. Consequently, the Layer 3 source IP address in the IP header arriving at App-B's network interface is the Bastion's primary private IP (`10.10.1.10`), not the student's WAN IP.

### Q4: Why does an 'Active' VPC peering status not guarantee that ping or SSH will succeed?
**Answer**: An "Active" peering connection merely signifies that the logical bilateral handshake between the two VPCs has been accepted. Traffic flow depends on two additional independent systems:
1. **Subnet Route Tables**: Both subnets must have static routes directing the target CIDR blocks to the peering interface.
2. **Security Groups**: Stateful host firewalls must explicitly permit incoming packets on the specific protocol and port from the originating IP. If either routes or firewall rules are missing, traffic will fail despite an Active peering state.

### Q5: Can VPC B access the Internet through VPC A's Internet Gateway over this peering connection?
**Answer**: **No.** AWS VPC Peering is strictly **non-transitive** and does not support edge routing to an Internet Gateway, NAT Gateway, Virtual Private Gateway, or Gateway Load Balancer across a peer. VPC peering only permits direct communication between resources with private IPs within the two paired VPCs.

---

## 7. CLEANUP & TEARDOWN VERIFICATION

To uphold cloud financial hygiene and prevent unwanted AWS usage charges:
1. Executed `terraform destroy` on the project root.
2. Verified in AWS Console:
   - [x] All 3 EC2 instances (`ewb-bastion`, `ewb-app-a`, `ewb-app-b`) in `Terminated` state.
   - [x] Attached 8GB gp3 EBS volumes deleted automatically (`delete_on_termination = true`).
   - [x] Security groups `ewb-sg-*` and route tables `ewb-rt-*` destroyed.
   - [x] Peering connection `ewb-a-b-peer` deleted.
   - [x] Both VPCs `ewb-vpc-a` and `ewb-vpc-b` deleted.

---

## 8. CONCLUSION & KEY LEARNINGS
Through this lab, I successfully demonstrated:
1. Creating non-overlapping CIDR networks (`10.10.0.0/16` and `10.20.0.0/16`) for enterprise cross-VPC interconnectivity.
2. Implementing Infrastructure as Code (IaC) using modular, declarative Terraform scripts with zero hardcoded credentials.
3. Leveraging SSH ProxyJump architecture to manage private cloud workloads securely without exposing them to public attack vectors.
4. Analyzing the difference between peering connection state, routing table entries, and security group enforcement.
