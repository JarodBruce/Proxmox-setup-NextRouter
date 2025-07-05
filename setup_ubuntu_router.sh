#!/bin/bash

# ==============================================================================
# Proxmox Ubuntu Router Auto-Deploy Script (Parallel Edition)
# ==============================================================================
#
# This script automates the creation of six Ubuntu VMs on Proxmox,
# configured to act as routers and clients using cloud-init and nftables.
#
# What it does:
# 1. Creates three new Linux Bridges on the Proxmox host: wan0, wan1, lan0.
# 2. Creates six Ubuntu VMs in parallel from a specified cloud-init ready template:
#    - Router 0: Connected to vmbr0 ↔ wan0
#    - Router 1: Connected to vmbr0 ↔ wan1
#    - NextRouter: Connected to wan0 ↔ wan1 ↔ lan0 (multi-homed bridge)
#    - LAN0 VM 1-3: Connected to lan0 (client VMs)
# 3. Uses cloud-init to:
#    - Set the hostname, user, and inject an SSH public key.
#    - Configure static IP addresses or DHCP for all interfaces.
#    - Install nftables and configure firewalls for router VMs.
#    - Set up NAPT (masquerade) rules to NAT traffic from LAN to WAN.
#    - Configure basic firewall rules for forwarding.
#    - Enable IP forwarding in the kernel for router VMs.
# 4. Starts all VMs in parallel for faster deployment.
# 5. Parallel VM creation to speed up deployment.
#
# ==============================================================================

# --- Configuration ---
# Load configuration from .env file
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE"
    set -a  # Automatically export all variables
    source "$ENV_FILE"
    set +a  # Turn off automatic export
else
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create a .env file with your configuration."
    exit 1
fi

# --- End of Configuration ---

# Display loaded configuration
echo "=========================================="
echo "Configuration loaded successfully:"
echo "Template VM ID: ${TEMPLATE_VM_ID}"
echo "Router VMs: ${ROUTER0_VM_ID} (${ROUTER0_VM_NAME}), ${ROUTER1_VM_ID} (${ROUTER1_VM_NAME})"
echo "NextRouter VM: ${NEXTROUTER_VM_ID} (${NEXTROUTER_VM_NAME})"
echo "LAN0 VMs: ${LAN0_VM1_ID}, ${LAN0_VM2_ID}, ${LAN0_VM3_ID}"
echo "VM Resources: ${MEMORY}MB RAM, ${CORES} cores, ${DISK_SIZE} disk"
echo "Bridges: ${LAN_BRIDGE}, ${WAN1_BRIDGE}, ${WAN2_BRIDGE}, ${UNUSED_BRIDGE}"
echo "=========================================="
echo

# Validate required settings
if [ -z "${TEMPLATE_VM_ID}" ]; then
    echo "Error: TEMPLATE_VM_ID is required but not set"
    exit 1
fi

if ! qm status ${TEMPLATE_VM_ID} >/dev/null 2>&1; then
    echo "Error: Template VM ${TEMPLATE_VM_ID} does not exist"
    echo "Please create an Ubuntu Cloud-Init template first"
    exit 1
fi

echo "Template VM ${TEMPLATE_VM_ID} found and ready."
echo

# --- Script Body ---
# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Function to process cloud-config template with variable substitution
process_cloud_config_template() {
    local template_file="$1"
    local output_file="$2"
    
    # Check if template file exists
    if [ ! -f "$template_file" ]; then
        echo "Error: Cloud-config template file not found: $template_file"
        exit 1
    fi
    
    # Process template with variable substitution
    envsubst < "$template_file" > "$output_file"
}

# Function to add a bridge to /etc/network/interfaces if it doesn't exist
add_bridge_if_not_exists() {
    local bridge_name=$1
    if ! grep -q "iface ${bridge_name}" /etc/network/interfaces; then
        echo "Adding bridge '${bridge_name}' to /etc/network/interfaces..."
        cat <<EOF >> /etc/network/interfaces

auto ${bridge_name}
iface ${bridge_name} inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
EOF
        return 0 # Indicates that a change was made
    else
        echo "Bridge '${bridge_name}' already exists in config."
        return 1 # Indicates no change
    fi
}

echo "### 1. Creating Virtual Bridges on Proxmox Host ###"
echo "Creating bridges: ${WAN1_BRIDGE}, ${WAN2_BRIDGE}, ${UNUSED_BRIDGE}"
echo "Note: ${LAN_BRIDGE} (vmbr0) should already exist as the main bridge"
echo "Note: ${UNUSED_BRIDGE} will be used for lan0 VMs"
# A flag to track if a network restart is needed
network_changed=false

# Add bridges and track if changes were made
# Note: We don't add vmbr0 as it should already exist
add_bridge_if_not_exists ${WAN1_BRIDGE} && network_changed=true
add_bridge_if_not_exists ${WAN2_BRIDGE} && network_changed=true
add_bridge_if_not_exists ${UNUSED_BRIDGE} && network_changed=true

# If any bridges were added, apply the changes
if [ "$network_changed" = true ]; then
    echo "Applying network changes..."
    ifreload -a
    echo "Bridges ${WAN1_BRIDGE}, ${WAN2_BRIDGE}, ${UNUSED_BRIDGE} are ready."
else
    echo "All required bridges already configured."
fi
echo

echo "### 2. Preparing the Virtual Machines ###"
# Function to create a router VM
create_router_vm() {
    local vm_id=$1
    local vm_name=$2
    local lan_ip=$3
    local lan_gateway=$4
    local wan_ip=$5
    local wan_gateway=$6
    local wan_bridge=$7
    local dns_servers=$8
    
    echo "Creating VM ${vm_id} (${vm_name})..."
    
    # Stop and destroy the VM if it already exists to ensure a clean slate
    if qm status ${vm_id} >/dev/null 2>&1; then
        echo "VM ${vm_id} already exists. Stopping and destroying it for a fresh start."
        qm stop ${vm_id} --timeout 60 || true # Allow failure if already stopped
        qm destroy ${vm_id}
        # Wait for cleanup to complete
        sleep 2
    fi

    echo "Cloning template ${TEMPLATE_VM_ID} to new VM ${vm_id}..."
    qm clone ${TEMPLATE_VM_ID} ${vm_id} --name "${vm_name}" --full
    
    # Wait a moment for the clone operation to complete
    sleep 2
    
    echo "Configuring VM resources..."
    qm resize ${vm_id} scsi0 ${DISK_SIZE}
    qm set ${vm_id} --memory ${MEMORY} --cores ${CORES}
    
    # Set display to Standard VGA
    echo "Setting display to Standard VGA for VM ${vm_id}..."
    qm set ${vm_id} --vga std
    
    # Cloud-Init User configuration
    qm set ${vm_id} --ciuser "${USER_NAME}"
    echo "Setting password authentication for VM ${vm_id}..."
    qm set ${vm_id} --cipassword "password"

    # Network configuration
    echo "Setting network interfaces for VM ${vm_id}..."
    echo "  - eth0: ${LAN_BRIDGE} (LAN) - ${lan_ip}, gateway: ${lan_gateway}"
    echo "  - eth1: ${wan_bridge} (WAN) - ${wan_ip}, gateway: ${wan_gateway}"
    
    # Configure ipconfig with gateway if specified
    if [ -n "${lan_gateway}" ] && [ "${lan_gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig0 "ip=${lan_ip},gw=${lan_gateway}"
    else
        qm set ${vm_id} --ipconfig0 "ip=${lan_ip}"
    fi
    
    if [ -n "${wan_gateway}" ] && [ "${wan_gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig1 "ip=${wan_ip},gw=${wan_gateway}"
    else
        qm set ${vm_id} --ipconfig1 "ip=${wan_ip}"
    fi

    qm set ${vm_id} --nameserver "${dns_servers}"
    qm set ${vm_id} --searchdomain "${DOMAIN_NAME}"

    # Custom cloud-init script for nftables, IP forwarding, and DHCP
    temp_ci_file=$(mktemp)
    snippet_filename="ci-${vm_id}-$(basename ${temp_ci_file}).yaml"
    
    # Calculate DHCP parameters based on WAN IP
    local wan_network=$(echo "${wan_ip}" | cut -d'/' -f1 | cut -d'.' -f1-3)
    local router_ip=$(echo "${wan_ip}" | cut -d'/' -f1)
    local dhcp_start="${wan_network}.100"
    local dhcp_end="${wan_network}.200"
    local broadcast_ip="${wan_network}.255"
    local subnet_mask="255.255.255.0"
    local subnet_network="${wan_network}.0"
    
    # Export variables for envsubst
    export USER_NAME SSH_PUBLIC_KEY dns_servers
    export subnet_network dhcp_start dhcp_end router_ip broadcast_ip subnet_mask
    
    # Process cloud-config template
    process_cloud_config_template "$(dirname "$0")/${ROUTER_CLOUD_CONFIG}" "${temp_ci_file}"

    echo "Applying custom cloud-init configuration for VM ${vm_id}..."
    qm set ${vm_id} --cicustom "vendor=local:snippets/${snippet_filename}"
    mv "${temp_ci_file}" "/var/lib/vz/snippets/${snippet_filename}"

    # Attach network devices
    echo "Attaching network interfaces to VM ${vm_id}..."
    qm set ${vm_id} --net0 virtio,bridge=${LAN_BRIDGE}
    qm set ${vm_id} --net1 virtio,bridge=${wan_bridge}
    
    echo "VM ${vm_id} (${vm_name}) configured successfully."
    echo
}

# Function to create NextRouter VM (connected to wan0, wan1, lan0)
create_nextrouter_vm() {
    local vm_id=$1
    local vm_name=$2
    local wan0_ip=$3
    local wan0_gateway=$4
    local wan1_ip=$5
    local wan1_gateway=$6
    local lan0_ip=$7
    local lan0_gateway=$8
    local dns_servers=$9
    
    echo "Creating NextRouter VM ${vm_id} (${vm_name})..."
    
    # Stop and destroy the VM if it already exists to ensure a clean slate
    if qm status ${vm_id} >/dev/null 2>&1; then
        echo "VM ${vm_id} already exists. Stopping and destroying it for a fresh start."
        qm stop ${vm_id} --timeout 60 || true # Allow failure if already stopped
        qm destroy ${vm_id}
        # Wait for cleanup to complete
        sleep 2
    fi

    echo "Cloning template ${TEMPLATE_VM_ID} to new VM ${vm_id}..."
    qm clone ${TEMPLATE_VM_ID} ${vm_id} --name "${vm_name}" --full
    
    # Wait a moment for the clone operation to complete
    sleep 2
    
    echo "Configuring VM resources..."
    qm resize ${vm_id} scsi0 ${DISK_SIZE}
    qm set ${vm_id} --memory ${MEMORY} --cores ${CORES}
    
    # Set display to Standard VGA
    echo "Setting display to Standard VGA for VM ${vm_id}..."
    qm set ${vm_id} --vga std
    
    # Cloud-Init User configuration
    qm set ${vm_id} --ciuser "${USER_NAME}"
    echo "Setting password authentication for NextRouter VM ${vm_id}..."
    qm set ${vm_id} --cipassword "password"

    # Network configuration - three interfaces
    echo "Setting network interfaces for VM ${vm_id}..."
    echo "  - eth0: ${WAN1_BRIDGE} (WAN0) - ${wan0_ip}, gateway: ${wan0_gateway}"
    echo "  - eth1: ${WAN2_BRIDGE} (WAN1) - ${wan1_ip}, gateway: ${wan1_gateway}"
    echo "  - eth2: ${UNUSED_BRIDGE} (LAN0) - ${lan0_ip}, gateway: ${lan0_gateway}"
    
    # Configure ipconfig with gateway if specified
    if [ "${wan0_ip}" = "dhcp" ]; then
        qm set ${vm_id} --ipconfig0 "ip=dhcp"
    elif [ -n "${wan0_gateway}" ] && [ "${wan0_gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig0 "ip=${wan0_ip},gw=${wan0_gateway}"
    else
        qm set ${vm_id} --ipconfig0 "ip=${wan0_ip}"
    fi
    
    if [ "${wan1_ip}" = "dhcp" ]; then
        qm set ${vm_id} --ipconfig1 "ip=dhcp"
    elif [ -n "${wan1_gateway}" ] && [ "${wan1_gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig1 "ip=${wan1_ip},gw=${wan1_gateway}"
    else
        qm set ${vm_id} --ipconfig1 "ip=${wan1_ip}"
    fi
    
    if [ "${lan0_ip}" = "dhcp" ]; then
        qm set ${vm_id} --ipconfig2 "ip=dhcp"
    elif [ -n "${lan0_gateway}" ] && [ "${lan0_gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig2 "ip=${lan0_ip},gw=${lan0_gateway}"
    else
        qm set ${vm_id} --ipconfig2 "ip=${lan0_ip}"
    fi

    # Set DNS only if not using DHCP for all interfaces
    if [ "${wan0_ip}" != "dhcp" ] || [ "${wan1_ip}" != "dhcp" ] || [ "${lan0_ip}" != "dhcp" ]; then
        qm set ${vm_id} --nameserver "${dns_servers}"
        qm set ${vm_id} --searchdomain "${DOMAIN_NAME}"
    fi

    # Custom cloud-init script for NextRouter
    temp_ci_file=$(mktemp)
    snippet_filename="ci-${vm_id}-$(basename ${temp_ci_file}).yaml"
    
    # Export variables for envsubst
    export USER_NAME SSH_PUBLIC_KEY dns_servers

    # Process cloud-config template
    process_cloud_config_template "$(dirname "$0")/${NEXTROUTER_CLOUD_CONFIG}" "${temp_ci_file}"

    echo "Applying custom cloud-init configuration for VM ${vm_id}..."
    qm set ${vm_id} --cicustom "vendor=local:snippets/${snippet_filename}"
    mv "${temp_ci_file}" "/var/lib/vz/snippets/${snippet_filename}"

    # Attach network devices (wan0, wan1, lan0)
    echo "Attaching network interfaces to NextRouter VM ${vm_id}..."
    qm set ${vm_id} --net0 virtio,bridge=${WAN1_BRIDGE}
    qm set ${vm_id} --net1 virtio,bridge=${WAN2_BRIDGE}
    qm set ${vm_id} --net2 virtio,bridge=${UNUSED_BRIDGE}
    
    echo "NextRouter VM ${vm_id} (${vm_name}) configured successfully."
    echo
}

# Function to create a simple VM connected to lan0 bridge
create_lan0_vm() {
    local vm_id=$1
    local vm_name=$2
    local ip_cidr=$3
    local gateway=$4
    local dns_servers=$5
    
    echo "Creating LAN0 VM ${vm_id} (${vm_name})..."
    
    # Stop and destroy the VM if it already exists to ensure a clean slate
    if qm status ${vm_id} >/dev/null 2>&1; then
        echo "VM ${vm_id} already exists. Stopping and destroying it for a fresh start."
        qm stop ${vm_id} --timeout 60 || true # Allow failure if already stopped
        qm destroy ${vm_id}
        # Wait for cleanup to complete
        sleep 2
    fi

    echo "Cloning template ${TEMPLATE_VM_ID} to new VM ${vm_id}..."
    qm clone ${TEMPLATE_VM_ID} ${vm_id} --name "${vm_name}" --full
    
    # Wait a moment for the clone operation to complete
    sleep 2
    
    echo "Configuring VM resources..."
    qm resize ${vm_id} scsi0 ${DISK_SIZE}
    qm set ${vm_id} --memory ${MEMORY} --cores ${CORES}
    
    # Set display to Standard VGA
    echo "Setting display to Standard VGA for VM ${vm_id}..."
    qm set ${vm_id} --vga std
    
    # Cloud-Init User configuration
    qm set ${vm_id} --ciuser "${USER_NAME}"
    echo "Setting password authentication for LAN0 VM ${vm_id}..."
    qm set ${vm_id} --cipassword "password"

    # Network configuration - single interface on lan0
    echo "Setting network interface for VM ${vm_id}..."
    echo "  - eth0: ${UNUSED_BRIDGE} (LAN0) - ${ip_cidr}, gateway: ${gateway}"
    
    # Configure ipconfig with gateway if specified
    if [ "${ip_cidr}" = "dhcp" ]; then
        qm set ${vm_id} --ipconfig0 "ip=dhcp"
    elif [ -n "${gateway}" ] && [ "${gateway}" != "" ]; then
        qm set ${vm_id} --ipconfig0 "ip=${ip_cidr},gw=${gateway}"
    else
        qm set ${vm_id} --ipconfig0 "ip=${ip_cidr}"
    fi

    # Set DNS only if not using DHCP
    if [ "${ip_cidr}" != "dhcp" ]; then
        qm set ${vm_id} --nameserver "${dns_servers}"
        qm set ${vm_id} --searchdomain "${DOMAIN_NAME}"
    fi

    # Basic cloud-init script (no routing/firewall needed)
    temp_ci_file=$(mktemp)
    snippet_filename="ci-${vm_id}-$(basename ${temp_ci_file}).yaml"
    
    # Export variables for envsubst
    export USER_NAME SSH_PUBLIC_KEY dns_servers

    # Process cloud-config template
    process_cloud_config_template "$(dirname "$0")/${LAN0_CLOUD_CONFIG}" "${temp_ci_file}"

    echo "Applying custom cloud-init configuration for VM ${vm_id}..."
    qm set ${vm_id} --cicustom "vendor=local:snippets/${snippet_filename}"
    mv "${temp_ci_file}" "/var/lib/vz/snippets/${snippet_filename}"

    # Attach network device to lan0
    echo "Attaching network interface to VM ${vm_id}..."
    qm set ${vm_id} --net0 virtio,bridge=${UNUSED_BRIDGE}
    
    echo "VM ${vm_id} (${vm_name}) configured successfully."
    echo
}

# Create VMs sequentially to avoid storage lock conflicts
echo "### 3. Creating Virtual Machines in Parallel ###"
echo "Starting parallel VM creation. This may take a few minutes..."
echo "========================================================"

# Array to store background process IDs
declare -a CREATE_PIDS=()

# Create Router VMs in parallel
(
    create_router_vm "${ROUTER0_VM_ID}" "${ROUTER0_VM_NAME}" \
        "${ROUTER0_LAN_IP_CIDR}" "${ROUTER0_LAN_GATEWAY}" \
        "${ROUTER0_WAN_IP_CIDR}" "${ROUTER0_WAN_GATEWAY}" \
        "${WAN1_BRIDGE}" "${ROUTER0_DNS}" \
        "${ROUTER0_DHCP_START}" "${ROUTER0_DHCP_END}"
) &
CREATE_PIDS+=($!)

(
    create_router_vm "${ROUTER1_VM_ID}" "${ROUTER1_VM_NAME}" \
        "${ROUTER1_LAN_IP_CIDR}" "${ROUTER1_LAN_GATEWAY}" \
        "${ROUTER1_WAN_IP_CIDR}" "${ROUTER1_WAN_GATEWAY}" \
        "${WAN2_BRIDGE}" "${ROUTER1_DNS}" \
        "${ROUTER1_DHCP_START}" "${ROUTER1_DHCP_END}"
) &
CREATE_PIDS+=($!)

# Create NextRouter VM in parallel
(
    create_nextrouter_vm "${NEXTROUTER_VM_ID}" "${NEXTROUTER_VM_NAME}" \
        "${NEXTROUTER_WAN0_IP_CIDR}" "${NEXTROUTER_WAN0_GATEWAY}" \
        "${NEXTROUTER_WAN1_IP_CIDR}" "${NEXTROUTER_WAN1_GATEWAY}" \
        "${NEXTROUTER_LAN0_IP_CIDR}" "${NEXTROUTER_LAN0_GATEWAY}" \
        "${NEXTROUTER_DNS}"
) &
CREATE_PIDS+=($!)

# Create LAN0 VMs in parallel
(
    create_lan0_vm "${LAN0_VM1_ID}" "${LAN0_VM1_NAME}" \
        "${LAN0_VM1_IP_CIDR}" "${LAN0_VM1_GATEWAY}" "${LAN0_VM1_DNS}"
) &
CREATE_PIDS+=($!)

(
    create_lan0_vm "${LAN0_VM2_ID}" "${LAN0_VM2_NAME}" \
        "${LAN0_VM2_IP_CIDR}" "${LAN0_VM2_GATEWAY}" "${LAN0_VM2_DNS}"
) &
CREATE_PIDS+=($!)

(
    create_lan0_vm "${LAN0_VM3_ID}" "${LAN0_VM3_NAME}" \
        "${LAN0_VM3_IP_CIDR}" "${LAN0_VM3_GATEWAY}" "${LAN0_VM3_DNS}"
) &
CREATE_PIDS+=($!)

# Wait for all creation processes to complete
echo "Waiting for all VM creation processes to complete..."
for pid in "${CREATE_PIDS[@]}"; do
    if ! wait $pid; then
        echo "Error: A VM creation process failed. Check logs for details."
        # Optional: kill remaining background jobs
        # kill "${CREATE_PIDS[@]}"
        exit 1
    fi
done

echo "All VM creation processes completed successfully!"
echo

echo "========================================================"
echo "### 4. Starting All Virtual Machines in Parallel ###"
echo "========================================================"

# Array to store background process IDs for starting VMs
declare -a START_PIDS=()

# Function to start a VM and handle errors
start_vm() {
    local vm_id=$1
    echo "Starting VM ${vm_id}..."
    qm start ${vm_id}
    if ! qm start ${vm_id}; then
        echo "Error starting VM ${vm_id}. Please check the Proxmox task log."
    fi
}

# Start all VMs in parallel
( start_vm ${ROUTER0_VM_ID} ) &
START_PIDS+=($!)
( start_vm ${ROUTER1_VM_ID} ) &
START_PIDS+=($!)
( start_vm ${NEXTROUTER_VM_ID} ) &
START_PIDS+=($!)
( start_vm ${LAN0_VM1_ID} ) &
START_PIDS+=($!)
( start_vm ${LAN0_VM2_ID} ) &
START_PIDS+=($!)
( start_vm ${LAN0_VM3_ID} ) &
START_PIDS+=($!)

# Wait for all start processes to complete
echo "Waiting for all VMs to start..."
for pid in "${START_PIDS[@]}"; do
    wait $pid
done

echo "All VMs have been started."
echo

echo "========================================================"
echo "### Deployment Summary ###"
echo "========================================================"
echo "The following VMs have been created and started:"
echo "  - Router 0 (${ROUTER0_VM_NAME}): VM ${ROUTER0_VM_ID}"
echo "    - LAN (eth0): ${ROUTER0_LAN_IP_CIDR} on ${LAN_BRIDGE}"
echo "    - WAN (eth1): ${ROUTER0_WAN_IP_CIDR} on ${WAN1_BRIDGE}"
echo "  - Router 1 (${ROUTER1_VM_NAME}): VM ${ROUTER1_VM_ID}"
echo "    - LAN (eth0): ${ROUTER1_LAN_IP_CIDR} on ${LAN_BRIDGE}"
echo "    - WAN (eth1): ${ROUTER1_WAN_IP_CIDR} on ${WAN2_BRIDGE}"
echo "  - NextRouter (${NEXTROUTER_VM_NAME}): VM ${NEXTROUTER_VM_ID}"
echo "    - WAN0 (eth0): ${NEXTROUTER_WAN0_IP_CIDR} on ${WAN1_BRIDGE}"
echo "    - WAN1 (eth1): ${NEXTROUTER_WAN1_IP_CIDR} on ${WAN2_BRIDGE}"
echo "    - LAN0 (eth2): ${NEXTROUTER_LAN0_IP_CIDR} on ${UNUSED_BRIDGE}"
echo "  - LAN0 VM 1 (${LAN0_VM1_NAME}): VM ${LAN0_VM1_ID} on ${UNUSED_BRIDGE}"
echo "  - LAN0 VM 2 (${LAN0_VM2_NAME}): VM ${LAN0_VM2_ID} on ${UNUSED_BRIDGE}"
echo "  - LAN0 VM 3 (${LAN0_VM3_NAME}): VM ${LAN0_VM3_ID} on ${UNUSED_BRIDGE}"
echo
echo "Deployment complete. It may take a few minutes for all VMs to be fully reachable."
echo "Default username: '${USER_NAME}', password: 'password'"
echo "========================================================"