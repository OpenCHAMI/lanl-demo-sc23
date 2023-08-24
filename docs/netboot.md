<!-- vim: set expandtab shiftwidth=2 softtabstop=2 textwidth=80: -->

# Setting Up Network Booting

- [Setting Up Network Booting](#setting-up-network-booting)
- [Scope](#scope)
- [Prerequisites](#prerequisites)
  * [`ipmitool`](#ipmitool)
  * [An Accessible BMC via IPMI](#an-accessible-bmc-via-ipmi)
    + [Configuring BMC Access](#configuring-bmc-access)
    + [Configuring Serial Over LAN (SOL)](#configuring-serial-over-lan-sol)
- [Configuring PXE Booting](#configuring-pxe-booting)

# Scope

The scope of this document is to cover how to take a system with stock firmware
settings, and configure it via IPMI to be able to boot over the network. This
document will use PXE as the network booting protocol, but HTTP boot support may
be added later.

# Prerequisites

## `ipmitool`

`ipmitool` will be used to communicate over the network via IPMI to the BMC to
configure network booting.

## An Accessible BMC via IPMI

It is presumed that the BMC can be accessed via IPMI (meaning that it can be
accessed via the network and the administrative credentials are known and can be
used to access it via IPMI). `ipmitool` will be used to send the BMC IPMI
commands.

### Configuring BMC Access

The BMC will either be configured to dynamically obtain its network settings or
have its network settings statically set. Whichever settings are present will
determine how to access the BMC to change settings.

1. **Dynamic Addressing (DHCP)**

   This way provides the easiest way of accessing the BMC, since one need only
   know the BMC's MAC address and have a DHCP server provide its IP address. The
   vendor will usually provide the MAC address and the administrative
   credentials.

2. **Static Addressing**

   If a static IP is configured (which is unlikely unless someone has changed
   the default settings), then accessing the BMC will require either knowing the
   static IP address and contacting the BMC using it through IPMI to change the
   settings or connecting with a KVM or crash cart and changing it through the
   UEFI firmware or BIOS settings.

Once the BMC has an IP address and the credentials are known, one can access
the BMC via IPMI with:

```
ipmitool -I lanplus -H <bmc_ip> -U <bmc_username> -P <bmc_password> <command>
```

`-P <password>` can be omitted to type it in interactively.

### Configuring Serial Over LAN (SOL)

To be able to view the console, the UEFI/BIOS firmware must be configured to
redirect console output over the BMC network connection. This setting is called
_Serial Over LAN (SOL)_, and, many times, this is disabled by default.

Configuring SOL can unfortunately be done only (as far as testing shows) via the
UEFI/BIOS firmware settings interface.

To do this, boot into the UEFI/BIOS firmware configuration interface and look
for a menu option resembling "serial console port redirection" and enable those
settings.

For instance, on the Gigabyte R272-Z32-00 nodes that are being used to test
this, the following settings under **Advanced** > **Serial Port Console
Redirection** would need to be set to **Enabled**:

- **Console Redirection**, under **COM1/SOL**
- **Console Redirection**, under **COM2**

Normally, you'd be able to do this via IPMI via:

```
# ipmitool -I lanplus -H <bmc_ip> -U <bmc_username> -P <bmc_password> sol set enabled true
```

however, this does not seem to actually update SOL settings in the firmware.

Alternatively, if the BMC is accessible via IPMI and SOL settings are set up
correctly, the UEFI/BIOS firmware settings menu can be accessed via the IPMI
console so that one need not be physically present to configure these settings.
To activate a serial console:

```
# ipmitool -I lanplus -H <bmc_ip> -U <bmc_username> -P <bmc_password> sol activate
```

To exit the console, the key combination is `~`+`.` (tilde, period).

**WARNING: The `~`+`.` combination is also the combination to exit SSH sessions.
If you are currently in one or more SSH sessions, prepend a tilde (`~`) for each
layer of SSH you are in.** For instance, if you are SSHed into a gateway, from
which you have an SSH session to the head node and you are accessing the IPMI
console from there, you would need two more tildes so the combination would be:
`~`+`~`+`~`+`.`.

If you get an error that a SOL session already exists when, in fact, one does
not (which sometimes happens when the SOL session is interrupted suddenly),
deactivate any existing sessions before activating a new one:

```
# ipmitool -I lanplus -H <bmc_ip> -U <bmc_username> -P <bmc_password> sol deactivate
```

# Configuring PXE Booting

Unfortunately, when testing on the Gigabyte R272-Z32-00 nodes, the IPMI commands
meant to do the particular tasks didn't perform what they were supposed to, so
going into the BIOS/UEFI firmware settings menu to change the settings had to be
performed. (Perhaps this could be changed with RedFish?)

Which interface to PXE boot from needs to be set. Boot into the UEFI/BIOS
firmware settings menu.

1. Go to the settings to configure the network booting device.

   On most AMI firmware (as in the case with the Gigabyte nodes), this will be
   under the **Boot** tab in **UEFI NETWORK Drive BBS Priorities**. Select this.

2. Set the network booting device to the desired interface.

   In this menu, there should be several boot options. In **Boot Option #1**,
   set this to the desired interface to PXE boot from. Sometimes, they will be
   all named the same (e.g. **UEFI: PXE IP4 Intel(R) I350 Gigabit Network
   Connection**). In this case, choose the one whose order in the list
   corresponds to the physical interface order. For example, if the interface
   corresponding to the first (e.g. left-most) interface is desired, choose the
   first one in the list.

   Then, press **Escape** to go back up one level.

3. Configure network booting as the first boot priority.

   Back in the top-level menu under the **Boot** tab, change **Boot Option #1**
   (under **FIXED BOOT ORDER Priorities** on Gigabyte) to be the network booting
   boot option. This will be named something like **Network:<net_iface>**, e.g.
   **Network:UEFI: PXE IP4 Intel(R) I350 Gigabit Network Connection**.

4. Save changes and exit.

   The node should be all set to PXE boot. Go to the **Save & Exit** menu and
   select **Save Changes and Exit**. The node will reboot and attempt to PXE
   boot.
