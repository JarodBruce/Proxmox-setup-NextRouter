#!/bin/bash

# ==============================================================================
# Proxmox Ubuntu Router Deletion Script
# ==============================================================================
#
# This script deletes the Ubuntu Router VMs created by setup_ubuntu_router.sh
# and cleans up associated cloud-init files.
#
# ==============================================================================

# --- Configuration ---
# Load configuration from .env file
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    set -a  # Turn on automatic export
    source "$ENV_FILE"
    set +a  # Turn off automatic export
    echo "Configuration loaded from $ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please ensure the .env file exists in the same directory as this script."
    exit 1
fi

# --- Script Body ---
set -euo pipefail

echo "### Deleting Ubuntu Router VMs ###"
echo ""
echo "Configuration loaded from .env file:"
echo "This will delete the following VMs:"
echo "=== Gateway VM ==="
echo "  - ${GATEWAY_VM_NAME} (VM ${GATEWAY_VM_ID})"
echo "=== Router VMs ==="
echo "  - ${ROUTER0_VM_NAME} (VM ${ROUTER0_VM_ID})"
echo "  - ${ROUTER1_VM_NAME} (VM ${ROUTER1_VM_ID})"
echo "  - ${NEXTROUTER_VM_NAME} (VM ${NEXTROUTER_VM_ID})"
echo "=== iPerf VMs ==="
echo "  - ${IPERF0_VM_NAME} (VM ${IPERF0_VM_ID})"
echo "  - ${IPERF1_VM_NAME} (VM ${IPERF1_VM_ID})"
echo "=== LAN0 VMs ==="
echo "  - ${LAN0_VM1_NAME} (VM ${LAN0_VM1_ID})"
echo "  - ${LAN0_VM2_NAME} (VM ${LAN0_VM2_ID})"
echo "  - ${LAN0_VM3_NAME} (VM ${LAN0_VM3_ID})"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Proceeding with deletion..."
echo ""

echo "### Deleting VMs in parallel ###"
echo "Starting parallel VM deletion..."

# Array to store background process IDs
declare -a DELETE_PIDS=()

# Stop and destroy Gateway VM
echo "Deleting Gateway VM..."
(
    if qm status ${GATEWAY_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting Gateway (VM ${GATEWAY_VM_ID})..."
        qm stop ${GATEWAY_VM_ID} --timeout 60 || true
        qm destroy ${GATEWAY_VM_ID}
        echo "✓ Gateway (VM ${GATEWAY_VM_ID}) deleted."
    else
        echo "⚠ Gateway (VM ${GATEWAY_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

# Stop and destroy Router VMs in parallel
echo "Deleting Router VMs in parallel..."
(
    if qm status ${ROUTER0_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting Router 0 (VM ${ROUTER0_VM_ID})..."
        qm stop ${ROUTER0_VM_ID} --timeout 60 || true
        qm destroy ${ROUTER0_VM_ID}
        echo "✓ Router 0 (VM ${ROUTER0_VM_ID}) deleted."
    else
        echo "⚠ Router 0 (VM ${ROUTER0_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

(
    if qm status ${ROUTER1_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting Router 1 (VM ${ROUTER1_VM_ID})..."
        qm stop ${ROUTER1_VM_ID} --timeout 60 || true
        qm destroy ${ROUTER1_VM_ID}
        echo "✓ Router 1 (VM ${ROUTER1_VM_ID}) deleted."
    else
        echo "⚠ Router 1 (VM ${ROUTER1_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

# Stop and destroy NextRouter VM
echo "Deleting NextRouter VM..."
(
    if qm status ${NEXTROUTER_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting NextRouter (VM ${NEXTROUTER_VM_ID})..."
        qm stop ${NEXTROUTER_VM_ID} --timeout 60 || true
        qm destroy ${NEXTROUTER_VM_ID}
        echo "✓ NextRouter (VM ${NEXTROUTER_VM_ID}) deleted."
    else
        echo "⚠ NextRouter (VM ${NEXTROUTER_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

# Stop and destroy iPerf VMs in parallel
echo "Deleting iPerf VMs in parallel..."
(
    if qm status ${IPERF0_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting iPerf-0 (VM ${IPERF0_VM_ID})..."
        qm stop ${IPERF0_VM_ID} --timeout 60 || true
        qm destroy ${IPERF0_VM_ID}
        echo "✓ iPerf-0 (VM ${IPERF0_VM_ID}) deleted."
    else
        echo "⚠ iPerf-0 (VM ${IPERF0_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

(
    if qm status ${IPERF1_VM_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting iPerf-1 (VM ${IPERF1_VM_ID})..."
        qm stop ${IPERF1_VM_ID} --timeout 60 || true
        qm destroy ${IPERF1_VM_ID}
        echo "✓ iPerf-1 (VM ${IPERF1_VM_ID}) deleted."
    else
        echo "⚠ iPerf-1 (VM ${IPERF1_VM_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

# Stop and destroy LAN0 VMs in parallel
echo "Deleting LAN0 VMs in parallel..."
(
    if qm status ${LAN0_VM1_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting LAN0 VM 1 (VM ${LAN0_VM1_ID})..."
        qm stop ${LAN0_VM1_ID} --timeout 60 || true
        qm destroy ${LAN0_VM1_ID}
        echo "✓ LAN0 VM 1 (VM ${LAN0_VM1_ID}) deleted."
    else
        echo "⚠ LAN0 VM 1 (VM ${LAN0_VM1_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

(
    if qm status ${LAN0_VM2_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting LAN0 VM 2 (VM ${LAN0_VM2_ID})..."
        qm stop ${LAN0_VM2_ID} --timeout 60 || true
        qm destroy ${LAN0_VM2_ID}
        echo "✓ LAN0 VM 2 (VM ${LAN0_VM2_ID}) deleted."
    else
        echo "⚠ LAN0 VM 2 (VM ${LAN0_VM2_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

(
    if qm status ${LAN0_VM3_ID} >/dev/null 2>&1; then
        echo "Stopping and deleting LAN0 VM 3 (VM ${LAN0_VM3_ID})..."
        qm stop ${LAN0_VM3_ID} --timeout 60 || true
        qm destroy ${LAN0_VM3_ID}
        echo "✓ LAN0 VM 3 (VM ${LAN0_VM3_ID}) deleted."
    else
        echo "⚠ LAN0 VM 3 (VM ${LAN0_VM3_ID}) not found."
    fi
) &
DELETE_PIDS+=($!)

# Wait for all deletion processes to complete
echo "Waiting for all VM deletion processes to complete..."
for pid in "${DELETE_PIDS[@]}"; do
    if wait "$pid"; then
        echo "✓ VM deletion process $pid completed successfully"
    else
        echo "✗ VM deletion process $pid failed"
        exit 1
    fi
done

echo "All VM deletion processes completed successfully!"
echo

# Clean up cloud-init files
echo "Cleaning up cloud-init files..."
removed_files=0
for file in /var/lib/vz/snippets/ci-${GATEWAY_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${ROUTER0_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${ROUTER1_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${NEXTROUTER_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${IPERF0_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${IPERF1_VM_ID}-*.yaml /var/lib/vz/snippets/ci-${LAN0_VM1_ID}-*.yaml /var/lib/vz/snippets/ci-${LAN0_VM2_ID}-*.yaml /var/lib/vz/snippets/ci-${LAN0_VM3_ID}-*.yaml; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        echo "✓ Removed: $(basename "$file")"
        ((removed_files++))
    fi
done

if [[ $removed_files -eq 0 ]]; then
    echo "⚠ No cloud-init files found to remove."
else
    echo "✓ $removed_files cloud-init file(s) removed."
fi

echo ""
echo "========================================================"
echo "### Deletion Complete ###"
echo ""
echo "The following VMs have been deleted:"
echo "=== Gateway VM ==="
echo "  - ${GATEWAY_VM_NAME} (VM ${GATEWAY_VM_ID})"
echo "=== Router VMs ==="
echo "  - ${ROUTER0_VM_NAME} (VM ${ROUTER0_VM_ID})"
echo "  - ${ROUTER1_VM_NAME} (VM ${ROUTER1_VM_ID})"
echo "  - ${NEXTROUTER_VM_NAME} (VM ${NEXTROUTER_VM_ID})"
echo "=== iPerf VMs ==="
echo "  - ${IPERF0_VM_NAME} (VM ${IPERF0_VM_ID})"
echo "  - ${IPERF1_VM_NAME} (VM ${IPERF1_VM_ID})"
echo "=== LAN0 VMs ==="
echo "  - ${LAN0_VM1_NAME} (VM ${LAN0_VM1_ID})"
echo "  - ${LAN0_VM2_NAME} (VM ${LAN0_VM2_ID})"
echo "  - ${LAN0_VM3_NAME} (VM ${LAN0_VM3_ID})"
echo ""
echo "Network bridges are still configured:"
echo "  - ${GATEWAY_BRIDGE} (Gateway network)"
echo "  - ${WAN1_BRIDGE} (First WAN network)"
echo "  - ${WAN2_BRIDGE} (Second WAN network)"
echo "  - ${UNUSED_BRIDGE} (Additional bridge)"
echo ""
echo "To remove bridges manually:"
echo "  1. Edit /etc/network/interfaces"
echo "  2. Remove the bridge sections"
echo "  3. Run: sudo ifreload -a"
echo ""
echo "Or use the bridge removal script if available."
echo "========================================================"
