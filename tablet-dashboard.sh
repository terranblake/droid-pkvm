#!/bin/bash

# Portrait Mode Tablet Dashboard for pKVM
# This script displays various system and Kubernetes metrics
# in a format optimized for portrait orientation

# Set terminal properties
export TERM=xterm-256color

# Set terminal colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

clear
echo -e "${BLUE}${BOLD}===== Android pKVM Dashboard ($(date)) =====${NC}\n"

# Show system info
echo -e "${GREEN}${BOLD}SYSTEM INFO:${NC}"
echo -e "${YELLOW}Memory Usage:${NC}"
free -h | grep -v +

echo -e "\n${YELLOW}CPU Usage:${NC}"
top -bn1 | head -n 5 | tail -n 4

echo -e "\n${YELLOW}Disk Usage:${NC}"
df -h / | grep -v Filesystem

echo -e "\n${GREEN}${BOLD}KUBERNETES RESOURCES:${NC}"
echo -e "${YELLOW}Nodes:${NC}"
kubectl get nodes

echo -e "\n${YELLOW}Deployments:${NC}"
kubectl get deployments --all-namespaces | head -n 10

echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods --all-namespaces | head -n 10

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc --all-namespaces | grep -E 'NodePort|LoadBalancer|NAMESPACE' | head -n 10

echo -e "\n${GREEN}${BOLD}NETWORK INFO:${NC}"
echo -e "${YELLOW}IP Address:${NC}"
ip addr show | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print $2}'

echo -e "\n${YELLOW}Open Ports:${NC}"
ss -tulpn | grep LISTEN | grep -v 127.0.0.1 | awk '{print $5}' | sort | head -n 5 || echo "No open ports found"

echo -e "\n${BLUE}${BOLD}==== Refresh with: ./tablet-dashboard.sh ====${NC}" 