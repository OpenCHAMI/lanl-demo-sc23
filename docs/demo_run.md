# OCHAMI Demo -  Run

This README covers how to run the OCHAMI demo and assumes some services are pre-configured. This will showcase the starting of a VM (called `ochami-vm`) that will start all the needed docker containers for a system discover and boot. The VM is booted out of an s3 instance running via minnio and configured with cloud-init. The cloud-init configs are hosted on a simple python http server. 

## OCHAMI VM creation

The demo uses libvirt for management of `ochami-vm` as libvirt is pretty easy to use and is widely available. Here is the xml dump of the `ochami-vm` config file:

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

The important bits outside the name and allocated CPU and memory (which are easly adjusted) are the interfaces. We have two in this case. The first is for internal management of the VM and used the default `virbr0` bridge. The second is a simple bridge that connects the VM to the cluster network, allowing it to talk to the computes. 

The VM is configured to boot via http. This requires some edits to the libvirt network. The default network is used here but a new one can be created if desired:

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

The important line here is the link to the EFI boot executable (`http://10.100.0.1:9000/efi/BOOTX64.EFI`). This is hosted in s3 and accessed via http. A `grub.cfg` is also hosted here and contains the kernel and initrd locations as well as the kernel parameters. This is all covered in detail in the configuration README. 

To actually start the VM simply run `virsh create ochami-vm.xml`. This is located in `/data/libvirt` for the demo. To connect to the console run `virsh console ochami-vm`. The VM will attempt to boot with PXE (ipv4 and ipv6) before http and I wasn't able to figure out how to change that. You can disconnect from the console with `ctl + ]` in case you miss the message. 

You should see the VM boot into a Rocky 8 OS (all the systemd fun stuff), and towards the end you'll see cloud-init run. The cloud-init configs are pretty lengthy and will be covered in more details in the config readme. You can view the configs in `/data/cloud/cloud-init/52\:54\:00\:7c\:52\:cc/` on cg-head

`ochami-vm` should now be reachable from `cg-head` via ssh using the IP listed in the libvirt network config (`10.1.0.2`) or by hostname (`ochami-vm`) if added to DNS or `/etc/hosts` 

## Microservice startup and scanning with Magellan

The cloud-init configuration should have dropped a docker compose file in `/etc/docker-compose/demo-compose.yaml`. It is not setup to auto start so that things can be demoed. To start the demo run `docker compose -f /etc/docker-compose/demo-compose.yaml up -d`. You should see it pull the container images and begin running them. The end state should look something like:

```bash
[+] Running 9/9
 ✔ Network docker-compose_smd  Created                                                                                                          0.1s 
 ✔ Network docker-compose_bss  Created                                                                                                          0.1s 
 ✔ Container postgres-smd      Started                                                                                                          0.1s 
 ✔ Container tftp-server       Started                                                                                                          0.1s 
 ✔ Container dhcpd-server      Started                                                                                                          0.1s 
 ✔ Container postgres-bss      Started                                                                                                          0.1s 
 ✔ Container smd-init          Started                                                                                                          0.1s 
 ✔ Container smd               Started                                                                                                          0.1s 
 ✔ Container bss               Started                                                                                                          0.0s 
```

A couple of health checks to make sure SMD and BSS are running.

SMD:

```bash
[root@ochami-vm ~]# curl http://ochami-vm:27779/hsm/v2/service/ready
{"code":0,"message":"HSM is healthy"
```

BSS:

```bash
[root@ochami-vm ~]# curl http://ochami-vm:27778/boot/v1/service/status
{"bss-status":"running"}
```



Now we should be ready to run Magellan to discover the nodes on our compute plane. 

```bash
docker run bikeshack/magellan:latest \ 
/magellan.sh \ 
--scan "--subnet 172.16.0.0/24 --port 443 --timeout 3" \ 
--collect "--user admin --pass password --host http://vm01 --port 27779"
```

The Magellan output is pretty verbose, but we can check to see if we have discovered things:

```bash
[root@ochami-vm ~]# curl -s http://vm01:27779/hsm/v2/State/Components | jq
{
  "Components": [
    {
      "ID": "x1000c1s7b9",
      "Type": "Node",
      "Enabled": false
    },
...
```

Awesome! Now we can add entries to BSS. Here is an example JSON payload:

```json
{
	"kernel": "http://10.100.0.1:9000/boot-images/efi-images/vmlinuz-4.18.0-477.21.1.el8_8.x86_64",
	"initrd": "http://10.100.0.1:9000/boot-images/efi-images/initramfs-4.18.0-477.21.1.el8_8.x86_64.img",
	"macs": ["b4:2e:99:a6:06:47","b4:2e:99:a6:61:ee","b4:2e:99:a9:37:bd","b4:2e:99:a6:63:39","b4:2e:99:a6:63:a1","b4:2e:99:a6:63:a9","b4:2e:99:a6:62:33","b4:2e:99:aa:33:7e","b4:2e:99:a6:61:9d"],
	"params": "nomodeset ro root=live:http://10.100.0.1:9000/boot-images/boot-images/rocky8.8-compute-fbeb4ae ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 console=ttyS0,115200 ip6=off ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/compute/"
}
```

A lot going on here but some important lines are the `kernel` and `initrd` entries. These point to our s3 instance. The list of `macs` comes from inspecting the `http://ochami-vm:27779/hsm/v2/Inventory/ComponentEndpoints` output. The `params` are the standard kernel parameters used during PXE booting. The interesting ones are `root=live:http://10.100.0.1:9000/boot-images/boot-images/rocky8.8-compute-fbeb4ae`, this again points to our s3 instance, while `ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/compute/` points to our cloud-init server, which provides basic configs to our computes (when they boot) 

There are other containers running in our docker compose setup. The `tftp-server` serves out a pre-built `ipxe.efi` binary and `dhcpd-server` is pretty self-explanatory. The only intersting part is that we point the iPXE request to our bss microservice `filename "http://172.16.0.253:27778/boot/v1/bootparameters?mac=${mac}";`. You can see the full `dhcpd.conf` in `/data/dhcpd/dhcpd.conf` . 

## Booting compute nodes

Now we can boot our compute nodes since all of our needed services are running. The power controls and console logs are accessed on `cg-head`, not in our `ochami-vm`. There's not a particular reason to do this other than it was already configured on `cg-head`.

Query the nodes we'd like to boot:

```bash
[root@cg-head]# pm -q cg[01-06]
on:      cg[01-06]
off:   
```

and power off if on:

```bash
[root@cg-head]# pm -0 cg[01-06]
Command completed successfully
```

Wait a few seconds for them to power off:

```bash
[root@cg-head]# pm -q cg[01-06]
on:      
off:     cg[01-06]
unknown: 
```

Then power them on:

```bash
[root@cg-head]# pm -1 cg[01-06]
Command completed successfully
```

Some of the nodes can be stubborn so repeated `pm -1` calls may be needed

Then we can connect to a console of one of our nodes

```bash
[root@cg-head]# conman cg02
```

You should see it go through the normal iPXE boot steps. Something like:

```bash
iPXE 1.0.0+ -- Open Source Network Boot Firmware -- http://ipxe.org
Features: DNS HTTP iSCSI TFTP SRP VLAN AoE EFI Menu

net1: b4:2e:99:a6:61:ee using i350 on 0000:c2:00.0 (open)
  [Link:up, TX:0 TXE:0 RX:0 RXE:0]
Configuring (net1 b4:2e:99:a6:61:ee).................. ok
net0: fe80::e61d:2dff:fea3:4b56/64 (inaccessible)
net1: 172.16.0.2/255.255.255.0 gw 172.16.0.254
net1: fe80::b62e:99ff:fea6:61ee/64
net2: fe80::b62e:99ff:fea6:61ef/64 (inaccessible)
Next server: 172.16.0.253
Filename: http://172.16.0.253:27778/boot/v1/bootscript?mac=b4:2e:99:a6:61:ee
http://172.16.0.253:27778/boot/v1/bootscript... ok
bootscript : 684 bytes [script]
http://10.100.0.1:9000/boot-images/efi-images/vmlinuz-4.18.0-477.21.1.el8_8.x86_64... ok
http://10.100.0.1:9000/boot-images/efi-images/initramfs-4.18.0-477.21.1.el8_8.x86_64.img... ok
```

And then hopefully something like:

```bash
Rocky Linux 8.8 (Green Obsidian)
Kernel 4.18.0-477.21.1.el8_8.x86_64 on an x86_64

cg02 login:
```

You can now ssh to the computes from ochami-vm:

```bash
[trcotton@ochami-vm ~]$ ssh cg02
Warning: Permanently added 'cg02,172.16.0.2' (ECDSA) to the list of known hosts.
Last login: Mon Oct 30 22:32:23 2023 from 172.16.0.253
```




