# Rancher PoC - High Availability

## Objectives

This set of scripts aims to simplify the deployment of a highly available Rancher Management Server on RKE.

It currently supports the following deployment options:
- with direct access to Internet
- Internet accessed via Proxy
- Airgap
- Zypper based or Yum based operating systems

The following files are crucial for your experience:
- `hosts.list` : List of target servers where Rancher will be deployed
- `00-vars.sh` : Configuration variables
- `00-prepare-airgap.sh` : Preparation for airgap deployment
- `01-os_preparation.sh` : OS validations and preparation
- `02-rke_deploy.sh` : RKE deployment
- `03-rancher_install.sh` : Rancher Management Server deployment
- `04-cleanup-destroy.sh` : Cleanup target servers to start over
- `05-def_gw-ipv6.sh` : Special configurations (remove and set default gw, disable ipv6...)

## Pre-requisites

### Systems

- 1 admin server
 > The server you will use to execute the scripts

- 3 rancher management servers
 > These 3 machines will for a 3 nodes RKE cluster which will hold the Rancher Management UI
 > The 3 nodes will have: ETCD role, Controlplane role and Worker role

The servers are deployed using classic standards
 > Fixed network settings
 > Internet access (with or without proxy) / Airgap deployment is also possible but not yet implemented in the scripts
 > Time should be well set
 > DNS should be correct
 > Firewall should be deactivated
 > ... the scripts are here to try and validate that all your settings are good for deployment.

### Network

The Rancher UI will need a FQDN which load balances the connections toward the Rancher Management Server nodes.

(optional) You may also need a wildcard FQDN to easily access your applications on the future K8S clusters you will then deploy.

## Usage

### Clone repository

```bash
git config --global http.sslVerify false
git clone http://git.zypp.fr/se/rancher-poc.git
cd rancher-poc
```

### hosts.list - List target nodes

This file contains the list of target nodes that will be members of the RKE cluster and host the Rancher Management Server.

1 FQDN or IP address by line.

### 00-vars.sh - Variables to be configured

The variables in this file will be used by the scripts.

Edit this file and setup everything according to your environment and the required deployment scenario (normal, proxy, airgap).

### 00-prepare-airgap.sh - Only for Airgap deployment

This script is only needed in case of an airgap deployment.

It must be run on a node with Internet access and will download everything needed for the next steps.

Once executed, copy the entire rancher-poc directory to the admin server (deployment node) and move forward with next scripts.

### 01-os_preparation.sh - Validations and OS preparation

Script to validate environment and setup pre-requisites.

```bash
./01-os_preparation.sh
```

### 02-rke_deploy.sh - RKE Cluster installation

Deploy a RKE cluster on target nodes.

```bash
./02-rke_deploy.sh
```

### 03-rancher_install.sh - Rancher Management Server installation

Deploy the Rancher Management Server on the previously deployed RKE cluster.

```bash
./03-rancher_install.sh
```

### 04-cleanup-destroy.sh - Cleanup (CAREFUL!)

Cleanup everything. There's no turning back.

```bash
./04-cleanup-destroy.sh
```

