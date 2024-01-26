# THIS REPOSITORY IS NOT ACTIVE

Our demo went great and we've moved on.  Much of what we learned is being used to create our [deployment-recipe](https://github.com/OpenCHAMI/deployment-recipes/tree/main/lanl/docker-compose) for the 2024 Supercomputer Institute at Los Alamos National Laboratory.

## ochami-lanl-dev
Demo Repository for ochami at LANL

At SC23, the ochami team at LANL will demostrate using microservices from the Open Source CSM repositories to discover and boot a set of HPC nodes.  The purpose of this demo isn't to release a production-ready system management product.  It is to demonstrate that the community can make progress with the existing codebase.

To show that the code can be safely modified to reduce the operational burden of a microservice, we're going to switch BSS to use a postgres backend instead of the current etcd backend.  This will reduce the number of dependent services while also targeting one of the areas of troubleshooting challenges the LANL team has identified with production CSM.

To show that the infrastructure complexity of CSM is optional where sites are willing to make different tradeoffs, we're going to deploy only a subset of the microservices with as little infrastructure as necessary.  The demo will not be HA or suitable for long-term production deployments.  It will run on a single host without Ceph, Kubernetes, Kafka, etc...

To demostrate the infrastructure modularity of ochami, our demo will not be using bundled solutions for Object Storage (S3), Container/Package Repositories, Container Storage Interface drivers, HTTP(S) Ingress/Reverse proxy, and many others.

To demostrate the software modularity of ochami, we will demonstrate that community redfish discovery software can be used to build the component inventory without MEDS or REDS.

To demonstrate component modularity, we will use an image build pipeline and management system that sits outside the system management host(s) and follow the cloud paradigm for post-boot customization with cloud-init.

The obvious next step for a project like this is to re-introduce deployment characteristics that take our simple demo and make it highly available. 

## Demo Goals

At SC23, we will demonstrate 

* discovery of all BMCs in a small HPC cluster using bmclib to populate SMD
* configuration of the inventoried HPC nodes to boot a custom built (non-IMS) HPC image over the HPC network (httpboot preferred)
* boot and post-boot configuration provided by bss and cloud-init with automatic DNS/DHCP registration
* bss running on a postgres backend instead of the etcd database

## Stretch Goals

* Boot an existing machine
* Use HMS tenancy to deploy two separate SLURM clusters on the HPC resources
* Run Jobs
