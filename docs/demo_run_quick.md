# OCHAMI Demo - Quick Run

## Contents

- [OCHAMI Demo - Quick Run](#ochami-demo---quick-run)
  - [Contents](#contents)
  - [Creating the OCHAMI VM](#creating-the-ochami-vm)
    - [Configuring the Network](#configuring-the-network)
    - [Configuring/Starting the VM](#configuringstarting-the-vm)
    - [Logging into the VM](#logging-into-the-vm)
  - [Starting Microservices](#starting-microservices)
  - [Discovering Nodes with Magellan](#discovering-nodes-with-magellan)
  - [Adding Node Boot Config](#adding-node-boot-config)
  - [Booting Compute Nodes](#booting-compute-nodes)
  - [Using the Booted Nodes](#using-the-booted-nodes)
  - [Cleanup](#cleanup)
    - [VM](#vm)
    - [Nodes](#nodes)
    - [SSH](#ssh)

## Creating the OCHAMI VM

### Configuring the Network

Bring down the default network to configure it:

```
[cg-head]# virsh net-destroy default
```

Create `ochami-net.xml`:

```xml
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
  <name>default</name>
  <uuid>729d1681-9b85-4ac2-b8b3-8e8718a1befd</uuid>
  <forward mode='open'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:fd:87:0e'/>
  <ip address='10.1.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.1.0.2' end='10.1.0.254'/>
      <host mac='52:54:00:7c:52:cc' name='ochami-vm' ip='10.1.0.2'/>
    </dhcp>
  </ip>
  <dnsmasq:options>
    <dnsmasq:option value='dhcp-vendorclass=set:efi-http,HTTPClient:Arch:00016'/>
    <dnsmasq:option value='dhcp-option-force=tag:efi-http,60,HTTPClient'/>
    <dnsmasq:option value='dhcp-boot=tag:efi-http,&quot;http://10.100.0.1:9000/efi/BOOTX64.EFI&quot;'/>
  </dnsmasq:options>
</network>
```

Create the default network from `ochami-net.xml`:

```
[cg-head]# virsh net-create ochami-net.xml
```

### Configuring/Starting the VM

Create `ochami-vm.xml` containing the VM config:

```xml
<domain type="kvm">
  <name>ochami-vm</name>
  <uuid>8b78362b-f162-49bc-a674-4e0a09ec6e1a</uuid>
  <memory>16777216</memory>
  <currentMemory>16777216</currentMemory>
  <vcpu>1</vcpu>
  <os>
    <type arch="x86_64" machine="q35">hvm</type>
    <loader readonly="yes" type="pflash" secure="yes">/usr/share/OVMF/OVMF_CODE.secboot.fd</loader>
    <boot dev="network"/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <smm state="on"/>
  </features>
  <cpu mode="host-model"/>
  <clock offset="utc">
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
  </clock>
  <pm>
    <suspend-to-mem enabled="no"/>
    <suspend-to-disk enabled="no"/>
  </pm>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    <interface type="network">
      <source network="default"/>
      <mac address="52:54:00:7c:52:cc"/>
      <model type="virtio"/>
    </interface>
    <interface type='bridge'>
      <source bridge="br0"/>
      <model type="virtio"/>
    </interface>
    <console type="pty"/>
  </devices>
</domain>
```

Create and start the VM (the default network must already be up) using
`ochami-vm.xml`:

```
[cg-head]# virsh create ochami-vm.xml
```

The VM will immediately try to boot. Connect the console via:

```
[cg-head]# virsh console ochami-vm
```

### Logging into the VM

If `ochami-vm` is present in the hosts file, login using:

```
[cg-head]$ ssh ochami-vm
```

Otherwise, use:

```
[cg-head]$ ssh 10.1.0.2
```

## Starting Microservices

Start the microservices and detach:

```
[ochami-vm]# docker compose -f /etc/docker-compose/demo-compose.yaml up -d
```

Check that SMD is up:

```
[ochami-vm]$ curl http://ochami-vm:27779/hsm/v2/service/ready
{"code":0,"message":"HSM is healthy"}
```

Check that BSS is up:

```
[ochami-vm]$ curl http://ochami-vm:27778/boot/v1/service/status
{"bss-status":"running"}
```

## Discovering Nodes with Magellan

Run Magellan in Docker and discover node information:

```
[ochami-vm]# docker run bikeshack/magellan:latest /magellan.sh --scan "--subnet 172.16.0.0/24 --port 443 --timeout 3" --collect "--user admin --pass password --host http://ochami-vm --port 27779"
```

Check if nodes were discovered:

```
[ochami-vm]$ curl -s http://ochami-vm:27779/hsm/v2/State/Components | jq
{
  "Components": [
    {
      "ID": "x1000c1s7b9",
      "Type": "Node",
      "Enabled": false
    },
    ...
  ]
}
```

Extract boot mac addresses from discovered node information:

```
[ochami-vm]$ curl http://ochami-vm:27779/hsm/v2/Inventory/ComponentEndpoints \
  | jq '.ComponentEndpoints[].RedfishSystemInfo.EthernetNICInfo[] | select(.RedfishId=="Onboard_0_0").MACAddress' \
  | tr '[A-Z]' '[a-z]'
```

The output will be akin to:

```
"b4:2e:99:a6:5b:f1"
"b4:2e:99:a6:06:47"
"b4:2e:99:a6:62:33"
"b4:2e:99:a6:61:9d"
"b4:2e:99:a6:63:39"
"b4:2e:99:a6:63:a9"
"b4:2e:99:a9:37:bd"
"b4:2e:99:a6:63:a1"
"b4:2e:99:a6:61:ee"
"b4:2e:99:aa:33:7e"
```

## Adding Node Boot Config

Using the collected MAC addresses above, create `bss-add-all.json` with the
following payload (put MAC addresses in `macs` field as a JSON array):

```json
{
        "macs": [
                "b4:2e:99:a6:5b:f1",
                "b4:2e:99:a6:06:47",
                "b4:2e:99:a6:61:ee",
                "b4:2e:99:a9:37:bd",
                "b4:2e:99:a6:63:39",
                "b4:2e:99:a6:63:a1",
                "b4:2e:99:a6:63:a9",
                "b4:2e:99:a6:62:33",
                "b4:2e:99:aa:33:7e",
                "b4:2e:99:a6:61:9d"
        ],
        "kernel": "http://10.100.0.1:9000/boot-images/efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64",
        "initrd": "http://10.100.0.1:9000/boot-images/efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img",
        "params": "nomodeset ro root=live:http://10.100.0.1:9000/boot-images/boot-images/rocky8.8-compute-1196423 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 console=ttyS0,115200 ip6=off ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/compute/"
}
```

Send this as a POST request to BSS to create the node config:

```
[ochami-vm]$ curl -X POST -H 'Content-Type: application/json' -d @bss-add-all.json http://ochami-vm:27778/boot/v1/bootparameters
```

Check that the boot config properly got added:

```
[ochami-vm]$ curl http://ochami-vm:27778/boot/v1/bootparameters | jq
```

The output should be:

```json
[
  {
    "macs": [
      "b4:2e:99:a6:5b:f1",
      "b4:2e:99:a6:06:47",
      "b4:2e:99:a6:61:ee",
      "b4:2e:99:a9:37:bd",
      "b4:2e:99:a6:63:39",
      "b4:2e:99:a6:63:a1",
      "b4:2e:99:a6:63:a9",
      "b4:2e:99:a6:62:33",
      "b4:2e:99:aa:33:7e",
      "b4:2e:99:a6:61:9d"
    ],
    "params": "nomodeset ro root=live:http://10.100.0.1:9000/boot-images/boot-images/rocky8.8-compute-1196423 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 console=ttyS0,115200 ip6=off ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/compute/",
    "kernel": "http://10.100.0.1:9000/boot-images/efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64",
    "initrd": "http://10.100.0.1:9000/boot-images/efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img",
     ...
  }
]
```

## Booting Compute Nodes

From `cg-head`, query the node power state:

```
[cg-head]$ pm -q
on:      cg[01-06]
off:
```

Make sure the nodes are powered off:

```
[cg-head]$ pm -0 cg[01-10]
Command completed successfully
```

Wait for them power off. To continually monitor, open another window and run:

```
[cg-head]$ watch pm -q
```

Then, power on all of the nodes with:

```
[cg-head]$ pm -1 cg[01-10]
```

Some of the nodes can be stubborn, so repeated `pm -1` calls may be necessary.

After the nodes have powered on, connect to one of the nodes' consoles:

```
[cg-head]$ conman cg02
```

## Using the Booted Nodes

Once the nodes have been booted, SSH into one of them **from the VM**:

```
[ochami-vm]$ ssh cg02
```

From the VM, check Slurm status:

```
[ochami-vm]$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
cluster*     up   infinite      6   idle cg[01-10]
```

Try running a Slurm job:

```
[ochami-vm]$ srun -N 5 echo HelloWorld
HelloWorld
HelloWorld
HelloWorld
HelloWorld
HelloWorld
```

## Cleanup

### VM

Shutdown and destroy the VM:

```
[cg-head]# virsh destroy ochami-vm
```

or:

```
[ochami-vm]# poweroff
```

### Nodes

Power off the nodes:

```
[cg-head]$ pm -0 cg[01-10]
```

### SSH

If `ochami-vm` is present in the hosts file and the hostname was used to login,
clean the SSH host key entry using:

```
[cg-head]$ ssh-keygen -R ochami-vm
```

Otherwise, use:

```
[cg-head]$ ssh-keygen -R 10.1.0.2
```

Also remove the node that was SSHed into, e.g:

```
[cg-head]$ ssh-keygen -R cg02
```
