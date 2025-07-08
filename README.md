# NextRouter - Proxmox Ubuntu Router Auto-Deploy Script

This script automates the creation of multiple Ubuntu VMs on Proxmox, configured as routers and clients in a complex network topology.

## Quick Start

**Run the deployment script**:
   ```bash
   chmod +x setup_ubuntu_router.sh
   ./setup_ubuntu_router.sh
   ```

**Clean up (if needed)**:
   ```bash
   chmod +x delete_ubuntu_routers.sh
   ./delete_ubuntu_routers.sh
   ```

## Configuration
```
                     [ubuntu-router-0(172.18.0.1)] ←[wan0(172.18.0.x/24)]→ [NextRouter(172.18.0.100{dhcp})]
                                ↑                                                         ↑
                        [gateway0(172.16.0.x/24)]                            [lan0 (192.168.1.x)]
                                ↓                                                         ↓
        [Gateway(172.16.0.1)] ←→ [172.16.0.10, 172.16.0.20]                   [LAN0 VMs (192.168.1.101-103)]
                                ↑                                                         ↑
                        [vmbr0(10.40.x.x/20)]                                [lan0 (192.168.1.x)]
                                ↓                                                         ↓
        [Gateway(172.16.0.1)] ←→ [172.16.0.10, 172.16.0.20]                   [LAN0 VMs (192.168.1.101-103)]
                                ↑                                                         ↑
                        [gateway0(172.16.0.x/24)]                            [lan0 (192.168.1.x)]
                                ↓                                                         ↓
                     [ubuntu-router-1(172.17.0.1)] ←[wan1(172.17.0.x/24)]→ [NextRouter(172.17.0.100{dhcp})]
```

## Default Credentials

- Username: `ubuntu` (configurable via `.env`)
- Password: `password`
- SSH: Password authentication enabled

**Important**: Change the default password for production use!