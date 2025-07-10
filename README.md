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

## Network Topology

The script creates a complex network topology with the following components:

- **Gateway**: Main router connecting to the internet (vmbr0 ↔ gateway0)
- **Router 0**: Second-tier router (gateway0 ↔ wan0)
- **Router 1**: Second-tier router (gateway0 ↔ wan1)
- **NextRouter**: Multi-homed bridge router (wan0 ↔ wan1 ↔ lan0)
- **iPerf-0**: Performance testing VM on wan0 network
- **iPerf-1**: Performance testing VM on wan1 network
- **LAN0 VMs**: Three client VMs on the lan0 network

## Network Diagram
```
                                                　　 [iPerf(172.18.0.101)]
                                                               ↑
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
                                                               ↓
                                                　　 [iPerf(172.17.0.101)]
```

## Performance Testing

The iPerf VMs are pre-configured with iPerf3 for network performance testing:

- **iPerf-0** (VM 9008): Connected to wan0 network for testing Router 0 performance
- **iPerf-1** (VM 9009): Connected to wan1 network for testing Router 1 performance

### iPerf3 Usage Examples

```bash
# Server mode (automatically started on boot)
systemctl status iperf3-server

# Client mode examples
iperf3 -c <server_ip>                    # Basic bandwidth test
iperf3 -c <server_ip> -u                 # UDP test
iperf3 -c <server_ip> -t 60              # 60-second test
iperf3 -c <server_ip> -b 100M             # Limit bandwidth to 100 Mbps
```

## Default Credentials

- Username: `ubuntu` (configurable via `.env`)
- Password: `password`
- SSH: Password authentication enabled

**Important**: Change the default password for production use!