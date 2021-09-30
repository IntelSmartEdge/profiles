```text
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2019-2021 Intel Corporation
```

# ESP profile for SE-O Demo Experience Kits

This directory contains profile for the Edge Software Provisioner required to provision a Demo Experience Kits on the Ubuntu 20.04 LTS.

This profile is based on [intel/rni-profile-base-ubuntu](https://github.com/intel/rni-profile-base-ubuntu)'s `slim` and `master` branches.
For more information regarding conventions and limitations please refer to [intel/rni-profile-base-ubuntu](https://github.com/intel/rni-profile-base-ubuntu)'s READMEs (both `master` and `slim` branch).

## How to set up the ESP and the profile

> At least two hosts are required:
> 1. Host of the ESP server - can be physical server, laptop or VM.
> 1. Server to be provisioned.

> On the provisioned server, hard drive/SSD should be a primary boot target.<br>
> USB should be one-time booted via boot menu.<br>
> This will ensure that when the live OS reboots, an Ubuntu will be booted into and the Experience Kits will be started.

1. Clone the Edge Software Provisioner to separate Linux box that will host the ESP server.
1. Customize the Edge Software Provisioner (ESP).<br>
   In `conf/config.yml` provide following entry to `profiles` (provide `git_username` and `git_token` if needed):
   ```
     - git_remote_url: https://github.com/smart-edge-open/profiles
       profile_branch: main
       profile_base_branch: ""
       git_username: ""
       git_token: ""
       name: SEO_DEK
       custom_git_arguments: --depth=1
   ```
1. Build the ESP (`build.sh`)<br>
   This will build artifacts needed for the ESP to work and clone the profiles.
1. (optional) Create USB (`makeusb.sh`, `flashusb.sh`)
1. Customize profile on disk:
   1. `ESP/data/usr/share/nginx/html/profile/SEO_DEK/files/seo/provision_settings`</br>
      This file contains GitHub token, URL to clone, branch to checkout on clone, and other settings.
   1. Provide customizations to the DEK execution:
      1. `ESP/data/usr/share/nginx/html/profile/SEO_DEK/files/seo/group_vars`<br>
         Most importantly `all.yml` file.
      1. `ESP/data/usr/share/nginx/html/profile/SEO_DEK/files/seo/host_vars`
1. Run the ESP (`run.sh`)
1. Boot the live system (uOS) via PXE or from USB on destination machine.<br>
   Live system will prepare Ubuntu for deployment of the Experience Kits which will happen after machine reboot and boot into Ubuntu system.

## Provisioning flow

1. uOS starts, fetches and executes `bootstrap.sh`.
   1. `bootstrap.sh` executes `pre.sh`, `profile.sh`, and `post.sh`
   1. `profile.sh` executes two files in order to provision the EK: 
      1. `provision_seo_common.sh`
         - SSH key generation
         - Pipenv installation
         - Systemd service `seo` installation and enabling
         - Cloning Experience Kits and installing dependencies
         - Fetching `group_vars` and `host_vars`
      2. `provision_seo_sn.sh` or `provision_seo_mn.sh`
         - Proper inventory file is downloaded
         - SSH certs are created (for multinode)
1. System reboots into provisioned OS (Ubuntu).
1. `seo` service starts on boot and runs Experience Kit.<br>
1. To check the status of the deployment:
   1. A message will be shown when initializing connection to the server using SSH:
      > Smart Edge Open Deployment Status: ...
   1. When logged in, logs can be inspected using:
      1. `journalctl -xefu seo`, or
      1. `tail -f /opt/seo/logs/seo_dek_...`
1. To restart the deployment, run a command:
   ```
   $ systemctl restart seo
   ```

## Experience Kit customization
Inside `files/seo` directory there are following directories used to customize the Experience Kit: `group_vars`, `host_vars`, and `sideload`.
Files in these `group_vars` and `host_vars` directories will be downloaded into Experience Kit inventory in following manner:
* `files/seo/group_vars/GROUP.yml` -> `inventory/default/group_vars/GROUP/100-settings.yml`,<br>
   e.g. `files/seo/group_vars/all.yml` will be saved as `inventory/default/group_vars/all/100-settings.yml` effectively overriding other files in that directory.
* `files/seo/host_vars/HOST.yml` -> `inventory/default/host_vars/HOST/100-settings.yml`

To side-load a file (e.g. `syscfg_package.zip` for BIOSFW):
1. Place the file in `esp/data/usr/share/nginx/html/profile/SEO_DEK/files/seo/sideload/` directory.
1. In `esp/data/usr/share/nginx/html/profile/SEO_DEK/files/seo/provision_setting` add an entry:
   ```
   files["syscfg_package.zip"]="biosfw/syscfg_package.zip"
   ```
   `syscfg_package.zip` will be downloaded into `/path-to-experience-kit/biosfw/syscfg_package.zip`<br>
   Schema is: `files["_NAME_OF_THE_FILE_IN_SIDELOAD_DIR"]="DESTINATION"`<br>
   More examples in `provision_setting` file.

## Relevant files for provisioning of Smart Edge Open

```
.
├── bootstrap.sh
├── files
│   └── seo
│       ├── group_vars
│       │   ├── all.yml
│       │   ├── controller_group.yml
│       │   └── edgenode_group.yml
│       ├── host_vars
│       │   ├── controller.yml
│       │   └── node01.yml
│       ├── inventories
│       │   ├── controller.yml
│       │   ├── node.yml
│       │   └── single_node.yml
│       ├── provision_seo_common.sh
│       ├── provision_seo_mn.sh
│       ├── provision_seo_sn.sh
│       ├── provision_settings
│       ├── sideload
│       └── systemd
│           ├── seo_deploy.sh
│           └── seo.service
├── post.sh
├── pre.sh
├── profile.sh
└── README.md
```
