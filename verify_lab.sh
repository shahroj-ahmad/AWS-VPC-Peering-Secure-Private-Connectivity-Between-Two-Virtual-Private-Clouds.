#!/bin/bash
# ==============================================================================
# EWB AWS VPC Peering - Automated Connectivity Verification Script
# Runs all tests from Page 11 of the Student Workbook
# ==============================================================================

set -e

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}===================================================================${RESET}"
echo -e "${CYAN}${BOLD}     AWS VPC PEERING PROJECT - AUTOMATED VERIFICATION SUITE         ${RESET}"
echo -e "${CYAN}${BOLD}===================================================================${RESET}"

# 1. Check local key
if [ ! -f ~/.ssh/ewb-lab.pem ]; then
    echo -e "${RED}[ERROR] Private key ~/.ssh/ewb-lab.pem not found!${RESET}"
    exit 1
fi

chmod 400 ~/.ssh/ewb-lab.pem

# 2. Get Bastion Public IP from terraform output
echo -e "\n${YELLOW}[1/5] Fetching outputs from Terraform...${RESET}"
if ! terraform output bastion_public_ip >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Terraform outputs not available. Run 'terraform apply' first.${RESET}"
    exit 1
fi

BASTION_IP=$(terraform output -raw bastion_public_ip)
echo -e "Bastion Public IP: ${GREEN}${BASTION_IP}${RESET}"

# 3. Test Bastion SSH
echo -e "\n${YELLOW}[2/5] Testing SSH connectivity to Bastion (${BASTION_IP})...${RESET}"
if ssh -i ~/.ssh/ewb-lab.pem -o StrictHostKeyChecking=no -o ConnectTimeout=8 ec2-user@${BASTION_IP} "echo Bastion connection SUCCESS" 2>/dev/null; then
    echo -e "${GREEN}✓ Bastion SSH: SUCCESS${RESET}"
else
    echo -e "${RED}✗ Bastion SSH: FAILED (Check your public IP in terraform.tfvars)${RESET}"
    exit 1
fi

# 4. Test SSH to App-A via ProxyJump
echo -e "\n${YELLOW}[3/5] Testing SSH to App-A (10.10.2.10) via Bastion ProxyJump...${RESET}"
if ssh -i ~/.ssh/ewb-lab.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ProxyJump=ec2-user@${BASTION_IP} ec2-user@10.10.2.10 "hostname; hostname -I" 2>/dev/null; then
    echo -e "${GREEN}✓ App-A SSH: SUCCESS${RESET}"
else
    echo -e "${RED}✗ App-A SSH: FAILED${RESET}"
fi

# 5. Test Forward Ping (App-A -> App-B: 10.20.1.10)
echo -e "\n${YELLOW}[4/5] Testing Forward Ping (App-A ➔ App-B: 10.20.1.10)...${RESET}"
ssh -i ~/.ssh/ewb-lab.pem -o StrictHostKeyChecking=no -o ProxyJump=ec2-user@${BASTION_IP} ec2-user@10.10.2.10 "ping -c 4 10.20.1.10" || echo -e "${RED}Ping failed (Are peering routes active?)${RESET}"

# 6. Test Reverse Ping (App-B -> App-A: 10.10.2.10)
echo -e "\n${YELLOW}[5/5] Testing Reverse Ping (App-B ➔ App-A: 10.10.2.10)...${RESET}"
ssh -i ~/.ssh/ewb-lab.pem -o StrictHostKeyChecking=no -o ProxyJump=ec2-user@${BASTION_IP} ec2-user@10.20.1.10 "ping -c 4 10.10.2.10" || echo -e "${RED}Reverse ping failed${RESET}"

echo -e "\n${CYAN}${BOLD}===================================================================${RESET}"
echo -e "${CYAN}${BOLD}                 VERIFICATION COMPLETED                            ${RESET}"
echo -e "${CYAN}${BOLD}===================================================================${RESET}"
