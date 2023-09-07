# ochami-lanl-dev
Demo Repository for ochami at LANL


## Demo Goals

At SC23, we will demonstrate 

* discovery of all BMCs in a small HPC cluster using bmclib to populate SMD
* configuration of the inventoried HPC nodes to boot a custom built (non-IMS) HPC image over the HPC network (httpboot preferred)
* boot and post-boot configuration provided by bss and cloud-init with automatic DNS/DHCP registration
* bss running on a postgres backend instead of the etcd database

## Stretch Goals

* Boot Trinity or some other existing machine
* Use HMS tenancy to deploy two separate SLURM clusters on the HPC resources
* Run Jobs
