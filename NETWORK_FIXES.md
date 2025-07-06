# Network Configuration Fixes

## Issues Found and Fixed

### 1. MAC Address Conflicts
**Problem**: All VMs cloned from the same template inherited identical MAC addresses, causing network conflicts.

**Solution**: 
- Added `generate_mac_address()` function to create unique MAC addresses based on VM ID and interface number
- Modified all network attachment commands to use unique MAC addresses:
  - Router VMs: `virtio,bridge=<bridge>,macaddr=<unique_mac>`
  - NextRouter VM: Each of the 3 interfaces gets a unique MAC
  - LAN0 VMs: Each gets a unique MAC for their single interface

### 2. IP Address Conflicts
**Problem**: NextRouter's LAN0 IP was set to `10.40.0.1/24` which conflicts with the gateway addresses used by other VMs.

**Solution**:
- Changed NextRouter's LAN0 IP from `10.40.0.1/24` to `192.168.100.1/24`
- This creates a separate network segment for the LAN0 VMs
- Added DHCP configuration variables for NextRouter

### 3. Missing DHCP Server for LAN0 Network
**Problem**: LAN0 VMs were configured for DHCP but no DHCP server was configured for the LAN0 network.

**Solution**:
- Added `isc-dhcp-server` package to NextRouter cloud-config
- Configured DHCP server to serve IP addresses in the 192.168.100.10-192.168.100.100 range
- Set NextRouter (192.168.100.1) as the gateway for LAN0 VMs
- Added firewall rules to allow DHCP traffic on eth2 (LAN0 interface)

### 4. Improved Network Routing
**Problem**: NextRouter had minimal forwarding rules and no NAT configuration.

**Solution**:
- Added specific forwarding rules for traffic between interfaces
- Added NAT rules to masquerade traffic from LAN0 to WAN interfaces
- This allows LAN0 VMs to access the internet through the router VMs

### 5. Fixed Script Bugs
**Problem**: The `start_vm()` function had a duplicate `qm start` command causing errors.

**Solution**:
- Removed duplicate command
- Added proper error handling and return codes

## Network Topology After Fixes

```
[Internet] ↔ [vmbr0 (10.40.0.x)] ↔ [Router 0] ↔ [wan0 (172.16.0.x)] ↔ [NextRouter] ↔ [lan0 (192.168.100.x)] ↔ [LAN0 VMs]
                                                                           ↕
[Internet] ↔ [vmbr0 (10.40.0.x)] ↔ [Router 1] ↔ [wan1 (172.30.0.x)] ↔ [NextRouter]
```

### IP Address Assignments:
- **Router 0**: 
  - LAN (eth0): `10.40.0.10/20` on vmbr0
  - WAN (eth1): `172.16.0.1/24` on wan0
  - DHCP range: `172.16.0.100-172.16.0.200`

- **Router 1**: 
  - LAN (eth0): `10.40.0.11/20` on vmbr0
  - WAN (eth1): `172.30.0.1/24` on wan1
  - DHCP range: `172.30.0.100-172.30.0.200`

- **NextRouter**: 
  - WAN0 (eth0): DHCP from Router 0 (172.16.0.x)
  - WAN1 (eth1): DHCP from Router 1 (172.30.0.x)
  - LAN0 (eth2): `192.168.100.1/24` on lan0
  - DHCP range: `192.168.100.10-192.168.100.100`

- **LAN0 VMs**: 
  - All use DHCP from NextRouter (192.168.100.x range)

## Benefits of These Fixes

1. **No MAC Address Conflicts**: Each VM has unique MAC addresses on all interfaces
2. **Proper Network Isolation**: Each network segment has its own IP range
3. **Working DHCP**: All VMs configured for DHCP will receive IP addresses
4. **Internet Access**: LAN0 VMs can access the internet through the router chain
5. **Scalable Design**: Easy to add more VMs or networks without conflicts

## Testing the Network

After deployment, you can test the network by:

1. **Check MAC addresses**: `qm config <VM_ID>` should show unique MAC addresses
2. **Check IP assignments**: SSH to VMs and run `ip addr show`
3. **Test connectivity**: Ping between different network segments
4. **Test internet access**: Try to ping external addresses from LAN0 VMs
5. **Check DHCP**: Verify that VMs receive IP addresses automatically

## Important Notes

- All VMs use the default password "password" - **change this for production use**
- The NextRouter acts as a multi-homed router connecting three networks
- Router 0 and Router 1 provide internet access to NextRouter
- NextRouter provides internet access to LAN0 VMs through NAT
