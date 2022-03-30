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
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bare_os=${param_bare_os}
# shellcheck disable=SC2269 # variable origin: pre.sh
scenario=${scenario}

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


# --- Upgrade installed packages ---
# shellcheck disable=SC2154
run "Upgrading packages on Ubuntu ${param_ubuntuversion}" \
    "docker run -i --rm --privileged --name ubuntu-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root ubuntu:${param_ubuntuversion} sh -c \
    'mount --bind dev /target/root/dev && \
    mount -t proc proc /target/root/proc && \
    mount -t sysfs sysfs /target/root/sys && \
    LANG=C.UTF-8 chroot /target/root sh -c \
    \"${INLINE_PROXY//\'/\\\"} export TERM=xterm-color && \
        export DEBIAN_FRONTEND=noninteractive && \
        apt update && \
        apt upgrade -y \"'" \
    "${PROVISION_LOG}"


primary_interface=$(ip route get 8.8.8.8 | head -n1 | awk '{print $5}')
primary_interface_mac=$(cat "/sys/class/net/${primary_interface}/address")
is_controller=no # multi-node

if [[ "${scenario}" = "single-node" ]]; then
    ssh_certs_mount=""
    scenario_info="single-node"
elif [[ "${scenario}" = "multi-node" ]]; then
    ssh_certs_mount="-v /hostroot/certs:/target/root/CAssh"

    if [ -z "${controller_mac}" ] || [ "${controller_mac}" = "${primary_interface_mac}" ]; then
        is_controller=yes
        scenario_info="multi-node/controlplane"
    else
        scenario_info="multi-node/node"
    fi
else
    run "Unknown scenario: $scenario. Exiting." \
        "false" \
        "${PROVISION_LOG}"
fi

run "Preparing host for Experience Kits. Scenario: ${scenario_info}" \
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
        export param_bare_os=$param_bare_os && \
        export is_controller=$is_controller && \
        export primary_interface=$primary_interface && \
        source <(wget --header \\\"Authorization: token ${param_token}\\\" -O- ${param_bootstrapurl}/files/seo/provision_settings) && \
        wget --header \\\"Authorization: token ${param_token}\\\" -O - ${param_bootstrapurl}/files/seo/provision_seo_common.sh | bash && \
        postfix=\\\$([[ \\\"\\\$scenario\\\" = \\\"single-node\\\" ]] && echo 'sn' || echo 'mn') && \
        wget --header \\\"Authorization: token ${param_token}\\\" -O- ${param_bootstrapurl}/files/seo/provision_seo_\\\$postfix.sh | bash && \
        echo finished\"'" \
    "${PROVISION_LOG}"
