# NextRouter - Proxmox Ubuntu Router Auto-Deploy Script

This script automates the creation of multiple Ubuntu VMs on Proxmox, configured as routers and clients in a complex network topology.

## Quick Start

1. **Configure your environment**:
   Copy the `.env` file and edit it with your settings:
   ```bash
   cp .env .env.local  # Optional: keep original as template
   # Edit .env with your preferred values
   ```

2. **Run the deployment script**:
   ```bash
   chmod +x setup_ubuntu_router.sh
   ./setup_ubuntu_router.sh
   ```

3. **Clean up (if needed)**:
   ```bash
   chmod +x delete_ubuntu_routers.sh
   ./delete_ubuntu_routers.sh
   ```

## Configuration

All configuration is done through the `.env` file. The script will automatically load settings from this file.

### VM Settings
- `TEMPLATE_VM_ID`: ID of the Ubuntu Cloud-Init template
- `ROUTER0_VM_ID`, `ROUTER1_VM_ID`: IDs for router VMs
- `NEXTROUTER_VM_ID`: ID for the NextRouter VM
- `LAN0_VM1_ID`, `LAN0_VM2_ID`, `LAN0_VM3_ID`: IDs for LAN0 client VMs

### VM Resources
- `MEMORY`: Memory allocation in MB (default: 2048)
- `CORES`: Number of CPU cores (default: 2)
- `DISK_SIZE`: Disk size (default: "32G")

### Network Configuration
- `LAN_BRIDGE`: Main LAN bridge (default: "vmbr0")
- `WAN1_BRIDGE`, `WAN2_BRIDGE`: WAN bridges (default: "wan0", "wan1")
- `UNUSED_BRIDGE`: Additional bridge for LAN0 VMs (default: "lan0")

### IP Address Configuration
Edit the `*_IP_CIDR` variables to set IP addresses for each VM.

### DNS and Gateway Configuration
Each VM can have its own DNS servers and gateway:
- `*_DNS`: DNS servers (comma-separated, e.g., "1.1.1.1,1.0.0.1")
- `*_GATEWAY`: Default gateway IP address (leave empty if no gateway needed)

Examples:
- `ROUTER0_DNS="1.1.1.1,1.0.0.1"`
- `ROUTER0_LAN_GATEWAY="10.40.0.1"`
- `LAN0_VM1_GATEWAY="192.168.100.1"`

## Network Topology

The script creates the following network topology:

```
[vmbr0 (10.40.0.x)] ←→ [wan0 (192.168.200.x)]
                               ↑
                         [NextRouter] ←→ [lan0 (192.168.100.x)] ←→ [LAN0 VMs (192.168.100.101-103)]
                               ↓
[vmbr0 (10.40.0.x)] ←→ [wan1 (192.168.201.x)]
```

## Features

- **Router VMs**: Two Ubuntu VMs configured as routers with nftables firewall and DHCP server
- **NextRouter VM**: Central router connecting multiple networks
- **LAN0 VMs**: Three client VMs connected to the LAN0 network
- **Automated Setup**: Cloud-init based configuration with SSH access
- **Parallel Deployment**: VMs are created and started in parallel for faster deployment

## Requirements

- Proxmox VE host
- Ubuntu Cloud-Init template (VM ID specified in .env)
- Sufficient resources for all VMs

## Default Credentials

- Username: `ubuntu` (configurable via `.env`)
- Password: `password`
- SSH: Password authentication enabled

**Important**: Change the default password for production use!