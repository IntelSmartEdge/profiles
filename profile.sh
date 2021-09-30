#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2019-2021 Intel Corporation

set -a

# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}
# shellcheck disable=SC2269 # variable origin: pre.sh
http_proxy=${http_proxy}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_username=${param_username}

# this is provided while using uOS
# shellcheck source=/dev/null
source /opt/bootstrap/functions

# --- Add Packages
ubuntu_bundles="openssh-server"
ubuntu_packages="wget git python3-pip arp-scan unattended-upgrades apt-config-auto-update"

# Packages to reach parity with default ISO install:
# - unattended-upgrades
# - apt-config-auto-update

# Other packages:
# - arp-scan for finding the controller's IP using MAC


# --- Install Extra Packages ---
# shellcheck disable=SC2154
run "Installing Extra Packages on Ubuntu ${param_ubuntuversion}" \
    "docker run -i --rm --privileged --name ubuntu-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root ubuntu:${param_ubuntuversion} sh -c \
    'mount --bind dev /target/root/dev && \
    mount -t proc proc /target/root/proc && \
    mount -t sysfs sysfs /target/root/sys && \
    LANG=C.UTF-8 chroot /target/root sh -c \
	\"${INLINE_PROXY//\'/\\\"} export TERM=xterm-color && \
        export DEBIAN_FRONTEND=noninteractive && \
        apt install -y tasksel && \
        tasksel install ${ubuntu_bundles} && \
        apt install -y ${ubuntu_packages} && \
        sed \\\"s,.*Banner.*,Banner /etc/issue.net,g\\\" -i /etc/ssh/sshd_config\"'" \
    "${PROVISION_LOG}"

# shellcheck source=./files/seo/provision_settings
source <(wget --header "Authorization: token ${param_token}" -O- "${param_bootstrapurl}/files/seo/provision_settings")
profile_name=$(echo "${param_bootstrapurl}" | cut -d'/' -f5)   # it assumes path: http(s)://PROVISIONER_IP/profile/PROFILE_NAME/bootstrap.sh
export profile_name
ssh_certs_mount="-v /certs:/target/root/CAssh"
if [[ "${scenario}" = "single-node" ]]; then
    ssh_certs_mount=""
fi

run "Preparing host for Experience Kits" \
    "docker run -i --rm --privileged --net=host --name ubuntu-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root ${ssh_certs_mount} ubuntu:${param_ubuntuversion} sh -c \
    'mount --bind dev /target/root/dev && \
    mount -t proc proc /target/root/proc && \
    mount -t sysfs sysfs /target/root/sys && \
    LANG=C.UTF-8 chroot /target/root bash -c \
	\"${INLINE_PROXY//\'/\\\"} export TERM=xterm-color && \
        export DEBIAN_FRONTEND=noninteractive && \
        export http_proxy=$http_proxy && \
        export https_proxy=$http_proxy && \
        export param_token=$param_token && \
        export param_bootstrapurl=$param_bootstrapurl && \
        export param_username=$param_username && \
        export profile_name=$profile_name && \
        source <(wget --header \\\"Authorization: token ${param_token}\\\" -O- ${param_bootstrapurl}/files/seo/provision_settings) && \
        wget --header \\\"Authorization: token ${param_token}\\\" -O - ${param_bootstrapurl}/files/seo/provision_seo_common.sh | bash && \
        postfix=\\\$([[ \\\"\\\$scenario\\\" = \\\"single-node\\\" ]] && echo 'sn' || echo 'mn') && \
        wget --header \\\"Authorization: token ${param_token}\\\" -O- ${param_bootstrapurl}/files/seo/provision_seo_\\\$postfix.sh | bash && \
        echo finished\"'" \
    "${PROVISION_LOG}"
