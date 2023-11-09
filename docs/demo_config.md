# Ochami Demo Configuration

This README covers how to install and configure the demo for OCHAMI

## Prerequisites

An installed OS is required to install the OS. We used RockyOS-8.7:

```bash
NAME="Rocky Linux"
VERSION="8.7 (Green Obsidian)"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.7"
PLATFORM_ID="platform:el8"
PRETTY_NAME="Rocky Linux 8.7 (Green Obsidian)"
ANSI_COLOR="0;32"
LOGO="fedora-logo-icon"
CPE_NAME="cpe:/o:rocky:rocky:8:GA"
HOME_URL="https://rockylinux.org/"
BUG_REPORT_URL="https://bugs.rockylinux.org/"
ROCKY_SUPPORT_PRODUCT="Rocky-Linux-8"
ROCKY_SUPPORT_PRODUCT_VERSION="8.7"
REDHAT_SUPPORT_PRODUCT="Rocky Linux"
REDHAT_SUPPORT_PRODUCT_VERSION="8.7"
```

Other RHEL flavoured ditros will probably work without much difference, but Debian/SUSE/whatevOS might be more work with different package names and file locations. 

Our metal server is called `is-head` in this document, but you can be creative as you want.

## Package installs

This is the complete list of packages needed for the demo:

```bash
dnf install \ 
podman \
libvirt \
grub2-efi-x64 \
shim-x64 \
qemu-kvm
```



## Container Services

Most of the services we'll use will be containerized.

Let's make a place to keep all our container configs and start scripts:

```bash
mkdir -p /data/containers
```



### Dummy Interface

Let's setup a `dummy` interface on our headnode. This will keep the container services in their own space.

First load the `dummy` module

```bash
modprobe dummy
```

The configure the interface.

```bash
ip link add d01 type dummy
ip addr add 10.100.0.1/24 dev d01
ip link set d01 up
```

Should now have an interface called `d01` with IP `10.100.0.1`:

```bash
[root@is-head ~]# ip a show dev d01
5: d01: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
    link/ether be:4d:bd:70:4f:34 brd ff:ff:ff:ff:ff:ff
    inet 10.100.0.1/24 scope global d01
       valid_lft forever preferred_lft forever
    inet6 fe80::bc4d:bdff:fe70:4f34/64 scope link 
       valid_lft forever preferred_lft forever
```



### cloud-init

We'll use `cloud-init` to do post-boot configurations for our VMs and eventually our computes. We'll keep this as simple as possible:

Make an area to keep the cloud-init configs:

```bash
 mkdir -p /data/cloud/cloud-init
```



This is our script to start the cloud-init server. 

```bash
#!/bin/bash
podman run \
	-d \
	--rm \
	--name cloud-init-server \
	-p 10.100.0.1:8000:8000 \
	--expose 8000 \
	-v /data/cloud/:/data/cloud-init \
	-w /data/cloud-init \
	python:latest \
	python3 -m http.server
```

We'll just use a `python` container image and keep persistent data in `/data/cloud`. Note that we bound it to the dummy interface we made above.

Let's save this and make it executable:

```bash
vim /data/containers/ci-start.sh
chmod 750 /data/containers/ci-start.sh 
```

Then run it and check that it's running:

```bash
/data/containers/ci-start.sh
...
podman ps
CONTAINER ID  IMAGE                            COMMAND               CREATED        STATUS        PORTS                      NAMES
b3bb23921433  docker.io/library/python:latest  python3 -m http.s...  6 minutes ago  Up 5 minutes  10.100.0.1:8000->8000/tcp  cloud-init-server
```

We have our server running but no configs. We will cover the configs later on. 



### Minio

We'll use `minio` as our s3 server. It's super easy to setup and the API works just like an AWS s3 instance for this demo. 

Make a persistent space to keep s3 objects

```bash
mkdir /data/minio/
```

Then let's make a start script:

```bash
#!/bin/bash
podman run \
	-d \
	-v /data/minio:/data \
	--name minio-server \
	-p 10.100.0.1:9000:9000 \
	-p 10.100.0.1:9001:9001 \
	-e "MINIO_ROOT_USER=admin" \
	-e "MINIO_ROOT_PASSWORD=admin123" \
	minio/minio:latest \
	server /data --console-address ":9001"
```

This will start our minio-server, but we'll need to configure some steps

First exec into our minio-server

```bash
podman exec -it minio-server bash
```

Once inside the container we'll run some minio commands to setup our s3. We're using the user `admin` password `admin123`. 

```bash
mc alias set local http://localhost:9000 admin admin123
```

Then create the buckets we'll need

```bash
mc mb local/efi
mc mb local/boot-images
```

And then allow anonymous downloads

```bash
mc anonymous set download local/efi
mc anonymous set download local/boot-images
```

## HTTP Boot config

This section covers the configuration for setting up http booting, which is how we will boot the demo VM

### Python helper scripts

You can interact with the minio s3 instance via python's `boto3` library

Here we'll have three helper scripts that are pretty limited, but you can do a lot more with the `boto3` library

The first is just a python script that will list the objects in a bucket

```python
#! /usr/bin/env python3
import os
import sys
from argparse import ArgumentParser
import json
import subprocess as subp
import boto3
boto3.compat.filter_python_deprecation_warnings()

credentials = {
    'endpoint_url': os.getenv('S3_URL'),
    'access_key': os.getenv('S3_ACCESS'),
    'secret_key': os.getenv('S3_SECRET')
}

def main():
    parser = ArgumentParser(description='Creates a bucket')
    parser.add_argument('--bucket-name',
                        dest='bucket_name',
                        action='store',
                        required=True,
                        help='the name of the bucket to create')
    args = parser.parse_args()

    s3 = boto3.resource('s3',
                        endpoint_url=credentials['endpoint_url'],
                        aws_access_key_id=credentials['access_key'],
                        aws_secret_access_key=credentials['secret_key'],
                        verify=False, use_ssl=False)

    bucket = s3.Bucket(args.bucket_name)
    if bucket.creation_date:
        print("Objects in bucket " + args.bucket_name)
        for obj in bucket.objects.all():
            print(obj.key)
    else:
        print("Bucket " + args.bucket_name + " does not exist")

if __name__ == '__main__':
    main()
```

The second is little more complex but just let's us push objects to a bucket

```python
#! /usr/bin/env python3
import os
import sys
from argparse import ArgumentParser
import json
import subprocess as subp
import boto3
boto3.compat.filter_python_deprecation_warnings()

credentials = {
    'endpoint_url': os.getenv('S3_URL'),
    'access_key': os.getenv('S3_ACCESS'),
    'secret_key': os.getenv('S3_SECRET')
}

def main():
    parser = ArgumentParser(description='Creates a bucket')
    parser.add_argument('--bucket-name',
                        dest='bucket_name',
                        action='store',
                        required=True,
                        help='the name of the bucket to create')
    parser.add_argument('--key-name',
                        dest='key_name',
                        action='store',
                        required=True,
                        help='the objects key name')
    parser.add_argument('--file-name',
                        dest='file_name',
                        action='store',
                        required=True,
                        help='the file to upload')
    args = parser.parse_args()

    print("Uploading " + args.file_name + " as " + args.key_name + " to bucket " + args.bucket_name)

    s3 = boto3.resource('s3',
                        endpoint_url=credentials['endpoint_url'],
                        aws_access_key_id=credentials['access_key'],
                        aws_secret_access_key=credentials['secret_key'],
                        verify=False, use_ssl=False)

    print("creating bucket " + args.bucket_name)
    bucket = s3.Bucket(args.bucket_name)
    if bucket.creation_date:
        bucket.upload_file(Filename=args.file_name,Key=args.key_name)
    else:
        print("Bucket " + args.bucket_name + " does not exist")

if __name__ == '__main__':
    main()
```

The last is so we can delete objects

```python
#! /usr/bin/env python3
import os
import sys
from argparse import ArgumentParser
import json
import subprocess as subp
import boto3
boto3.compat.filter_python_deprecation_warnings()

credentials = {
    'endpoint_url': os.getenv('S3_URL'),
    'access_key': os.getenv('S3_ACCESS'),
    'secret_key': os.getenv('S3_SECRET')
}

def main():
    parser = ArgumentParser(description='Creates a bucket')
    parser.add_argument('--bucket-name',
                        dest='bucket_name',
                        action='store',
                        required=True,
                        help='the name of the bucket to create')
    parser.add_argument('--key-name',
                        dest='key_name',
                        action='store',
                        required=True,
                        help='the objects key name')
    args = parser.parse_args()

    print("Deleting " + args.key_name + " from bucket " + args.bucket_name)

    s3 = boto3.resource('s3',
                        endpoint_url=credentials['endpoint_url'],
                        aws_access_key_id=credentials['access_key'],
                        aws_secret_access_key=credentials['secret_key'],
                        verify=False, use_ssl=False)

    bucket = s3.Bucket(args.bucket_name)
    if bucket.creation_date:
        s3.Object(args.bucket_name,args.key_name).delete()
    else:
        print("Bucket " + args.bucket_name + " does not exist")

if __name__ == '__main__':
    main()
```

These are named `s3_list`, `s3_push`, and `s3_del` respectively. For the demo dump these into `/data/s3-utils/bin`. You can add a helper script to `/data/s3-utils/s3-setups.sh`

```bash
#!/bin/bash
export S3_URL=http://10.100.0.1:9000
export S3_ACCESS=admin
export S3_SECRET=admin123
export PATH=$PATH:/data/s3-utils/bin
```

and just source it

```bash
source /data/s3-utils/s3-setup.sh
```

### VM Image

Before we go any further let's build an image for our virtual machine to boot into

This can be any OS really but we'll use the host OSto make things easy. 

First let's make a temporary directory to install packages to

```bash
mkdir /tmp/vm-image
```

Then install groups

```bash
dnf groupinstall --releasever=8 \
    --installroot /tmp/vm-image/ \ 
    "Minimal Install" \
    "Development Tools"
```

This is probably overkill 

Next let's add extra repos

```bash
dnf --setopt=reposdir=/tmp/vm-image/etc/yum.repos.d/ config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf --setopt=reposdir=/tmp/vm-image/etc/yum.repos.d/ config-manager --add-repo http://10.15.3.42/repo/el8/openhpc
dnf --setopt=reposdir=/tmp/vm-image/etc/yum.repos.d/ config-manager --add-repo http://10.15.3.42/repo/el8/openhpc/updates
```

The first one is to install docker. We're going to be using docker compose later on and I have found podman's implementation to be lacking

The next two are for installing slurmctld. This isn't strictly necessary and is coming from a local mirror of OpenHPC



Next let's install some specific packages we'll need

```bash
dnf install -y --releasever=8 \
    --installroot /tmp/vm-image/ \ 
    kernel \
    dracut-live \
    cloud-init \
    jq \
    vim \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    slurm-slurmctld-ohpc \
    slurm-ohpc \
    munge \
    nss_db \
    nfs-utils \
    NetworkManager-initscripts-updown
```

`nss_db` is used for user accounts and is not strictly necessary. Same for `nfs-utils`

Next we'll `chroot` into our image and rebuild the initramfs

```bash
chroot /tmp/vm-image
```

This won't be a proper chrooted environment but we just need to rebuild the initramfs

```bash
dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f
```

This will add the ability to download our image during boot and create an overlay on top of it.

Now let's push our `vmlinuz`, `initramfs` to s3

```bash
s3_push --bucket-name boot-images --key-name efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64 --file-name /tmp/vm-image/boot/vmlinuz-4.18.0-477.27.1.el8_8.x86_64
s3_push --bucket-name boot-images --key-name efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img --file-name /tmp/vm-image/boot/initramfs-4.18.0-477.27.1.el8_8.x86_64.img 
```

The specific versions may be different for your setup so keep that in mind

Now let's squash up our image

```bash
mksquashfs /tmp/vm-image/ ochami-vm-image.squashfs
```

And then upload this as well

```bash
s3_push --bucket-name boot-images --key-name vm-images/ochami-vm-image.squashfs --file-name ochami-vm-image.squashfs
```

Once everything is done we should be able to list everything

```
s3_list --bucket-name boot-images
```

Which should look something like

```bash
Objects in bucket boot-images
efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img
efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64
vm-images/ochami-vm-image.squashfs
```

### EFI and grub

Next we'll grab the the EFI binaries we need and setup our grub configs

The two EFI binaries we'll need are 

```bash
/boot/efi/EFI/BOOT/BOOTX64.EFI 
/boot/efi/EFI/rocky/grubx64.efi 
```

These are installed by the `grub2-efi-x64` and `shim-x64` packages. The locations may change depending on the OS in use

We'll push these to our `efi` bucket

```bash
s3_push --bucket-name efi --key-name BOOTX64.EFI --file-name /boot/efi/EFI/BOOT/BOOTX64.EFI
```

Then we need to configure grub. Start by making a place to keep configs

```bash
mkdir /data/grub
```

The `grub.cfg` will look like this

```bash
set prefix=(http,10.100.0.1:9000)/efi
configfile ${prefix}/grub.cfg-${net_default_mac}
```

We set the prefix to our s3 server

and tell it to load the `grub.cfg` with the associated MAC from the VM. We do this so we can have multiple VMs that can use different grub configs. 

The MAC address for our demo VM is `52:54:00:7c:52:cc`. This is generated and can be anything you choose so long as it is a valid MAC.

Our specific MAC specific `grub.cfg-52-54-00-7c-52-cc` looks like this

```bash
set default="1"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=10

menuentry 'Netboot Rocky8' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /boot-images/efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64 nomodeset ro root=live:http://10.100.0.1:9000/boot-images/vm-images/ochami-vm-image.squashfs ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 console=ttyS0,115200 ip6=off "ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/${net_default_mac}/"
        initrdefi /boot-images/efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img
}
```

Some notable things to look at here

Our `linuxefi` and `initrdefi` point to their counterparts in s3. the ones we built earlier

The `root=live:http://10.100.0.1:9000/boot-images/vm-images/ochami-vm-image.squashfs` also points to the image we built and pushed to s3

and finally `"ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/${net_default_mac}/"` is our cloud-init server. We haven't made any configs just yet but that is the next step. 

That trailing `/` after the MAC variable is really important so don't forget it

Finally let's push up our grub configs

```bash
s3_push --bucket-name efi --key-name grub.cfg-52:54:00:7c:52:cc  --file-name /data/grub/grub.cfg-52-54-00-7c-52-cc
```

The file name we use has a `-` separating MAC octets. This is just for convience to avoid  dealing with escape characters. The actual key name in s3 will need to be `grub.cfg-52:54:00:7c:52:cc`

Listing the objects in the `efi` bucket, we should see something like this

```bash
Objects in bucket efi
BOOTX64.EFI
grub.cfg
grub.cfg-52:54:00:7c:52:cc
```

### Cloud-init

Okay, now it's time to setup cloud-init. This can be really simple to begin with and grow as you need it. The full set of cloud-init configs will be posted at the end but we can start with some simple things to get us going

Since we'll be keying of the MAC address of the VM, we'll need to make a space for it. We started our cloud-init server to use `/data/cloud` to serve files from

So let's make it there

```bash
mkdir /data/cloud/cloud-init/52:54:00:7c:52:cc
```

let's go to that directory. Mind the escape characters

```bash
cd /data/cloud/cloud-init/52\:54\:00\:7c\:52\:cc/
```

We'll need three files here: `meta-data`, `user-data`, and `vendor-data`

`vendor-data` is just a blank file so

```bash
touch vendor-data
```

and move on

`meta-data` should look something like this

```bash
instance-id: demo123
local-hostname: ochami-vm
network-interfaces: |
  iface enp2s0 inet static
  address 172.16.0.253
  netmask 255.255.255.0
```

the only really important entries here are the `local-hostname` which `cloud-init` will use to set the hostname and the network-interfaces

The `user-data` file is the important file here and has all the cool stuff in it. It can also get a bit lengthy so we'll only cover the bare essentials here.

We make heavy use of the `write_files` cloud-init directive

The are all of the form 

```
write_files:
- content: | 
    some data here
  path: /path/to/file
  permissions: 0755
```

For example, we setup the authorized keys so that root can log in. Not great for security but great for debugging

```
- content: |
    ssh-rsa <pubkey-data> root@is-head
  path: /root/.ssh/authorized_keys
```

The `write_files` is a list so you can have as many as you want

Here we have a `base64` encoded munge key

```
- content: |
    zHtUkDIkKmsCtXAKcYRqh8PmC13Uwmn7Eo53KtRW3RisrcBTbEZiuvcp6Vgf1pqH/dW+Q1QJupQ/
    e40hvKutyYvTvPITRkMB+6laU3WCUh7t+qBXo1iWCPgd3VUXaMC3xCmiEXt898hrZnD/CouPW3cY
    kYIU/0EoE5hh3VGXTcvHeU7QTEvKtLEZpE+11Bcd4KioR7omH5bgRiKWxbndor3ngaUvmKjKr0xi
    Ieo4reuMgsuBKJwNkbuCoBbt1axbsnCMcH/u4o2aT8oIm5XWPv2RwiYOLJ8O+vb3/3Ry+iStlDFj
    ee08kNSO60KEfUguynObjIvxLR3NaXoF9cQZfCPoUlR4wgjLTWJ0Red/95iLHKUMaLFVvAQqbiof
    oNww2lzm1lxqLg+EPQYz9LatLi6zNH+kC8r9p6riruS2fyMdRpAEObfNAAaLL345iemDDA9ZSami
    BqoVqpN1wTAyR262JuEaYxQ7zWZlJsYIAKMwZLVlP/M3JevZFv+APbyyvw/2LstdjAJsdiAFWPC6
    uzFudqLojsN/ecOHtCXkf/clV+/td8opQLKsDTadedEzCFeBAr3AxCB12MANYKhQeK5pyF5kxX/h
    3ZI/ytTmgq1HbQB4X6Mn5K8HaTgLGhHfMEhoob968trGzYSiAvtqi6yOyQuw81BQlwWkzdo98zt7
    kncrqBaah46LsgnP0ZqJeYGBEC4SZb4kvhIELDtVLLcV+BAEX5X/txOvCfp45bu2NkEYyPZzzfYK
    /2XZXH0SCB5XFolThTmJtB56Jp7G9s5oBr5yUpA5cZyngpH/X3yMO6Fy7OWEeib6/1LxVnxKeNd3
    guGtmxsBXGNa0KL2yL6ckHRXuKSjlfpWBUR6C8HRVi9Nf/rpuvFaUQ9bH5pxwTKIYKMLr9mN7/Iz
    zosdHtV2Lo5GLnBDKjTjUIEMjw0s+fsQDxcgEQX0lRw1uwctTe0MtHzW4FIX0pI9zOb5ULb38ymN
    RA4ERHJHP1ZjMVpV6HW81uDlT3GKjQl6lmCHyjqqcWvuEKYob/802s7j3nNuzt/QrEBPW6E7moEF
    AkHoEWYn/8xlu9ZkfjnNtHwuCUalsgJE9YQNmZTQwi1FFCSY8FjErvi4k1aLeiSG89KT9edx4620
    cbhi53/WUxvrBJzLzKwcBlNtzJyNYURG5IH/CIEr73CwSM2v5qPmEoptkNuINAw6JCwtSHM0R+7Y
    05P24TRVYGNWuJlwoKvXsN54qYvKK72gy65OfS0UxSw4pvwCYkFGkH1Ty3feP0MRLeAUESD4YOd8
    FsbVFll6Gku6I3rDOn34d6sUM2Wl3rP3OGGXmfCcKj4Uu4NGtmIFlHFAG3ajdSx13Oo9KZpJJA==
  encoding: base64
  permissions: '0400'
  path: /etc/munge/munge.key
```

The next directive we make use of is `runcmd`. This really is just a list of commands you want cloud-init to run

```
runcmd:
- setenforce 0
- systemctl stop firewalld
- chown munge:munge /etc/munge/munge.key
- systemctl restart munge
- systemctl start slurmctld
- systemctl start docker
- ifdown enp2s0
- ifup enp2s0
- ip a
- mount -t nfs 172.16.0.254:/home /home
```

You can turn off firewalls and selinux and start/restart services, etc

I did find that the `mount` directive did not seem to handle nfs mounts very well

and I will admit I had issues with the cloud-init networking so I cheated and added the `ifdown` and `ifup` so that my secondary interface would actually get an IP

That is all we'll cover in this part of the cloud-init section and again, the full config wil be posted at the end



## Libvirt

 We'll use libvirt as our VM manager

The first thing is to make sure the `libvirtd` systemd service is running (`systemctl status libvirtd`)



Once it's running we need to configure our libvirt network to handle http boot requests

I just used the default network but you an make a new one if you want to

```bash
virsh net-edit default
```

Edit it to look something like

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

There are a few import parts here. The `dhcp` section has our VM MAC address list with an IP. This is just to make sure it keeps the same IP. 

The `dnsmasq` section is also important, especially the last line. Make sure this points towards our s3 instance `http://10.100.0.1:9000/efi/BOOTX64.EFI`

We next need to destroy the default network. 

```bash
virsh net-destroy default
```

Then start it again

```bash
virsh net-start default
```

You can save the output somewhere safe with 

```bash
virsh net-dumpxml default > /data/libvirt/default-net.xml
```



Now Lets make an actual VM. We'll use an xml config for this

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

We have this configured to use 1 CPU and 16G of memory.

The `devices` sections has two interfaces. The default network it will boot from and how you wil access it from your head node. The second interface uses the bridge we made earlier to access the internal cluster network



save this somewhere (`/data/libvirt/ochami-vm.xml`)

Then you can start it

```bash
virsh create /data/libvirt/ochami-vm.xml
```

and can watch the console with 

```bash
virsh console ochami-vm
```

The escape sequence is `ctl + ]` if you miss it

You can destroy it with 

```bash
virsh destroy ochami-vm
```




