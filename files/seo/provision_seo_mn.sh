#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

set -euo pipefail
set -x

# shellcheck disable=SC2269 # variable origin: provision_settings > provision_seo_common.sh
ek_path=${ek_path}

# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}

# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}

cd "${ek_path}" 

# Determine if machine is controlplane using MAC address
primary_interface=$(ip route get 8.8.8.8 | head -n1 | awk '{print $5}')
primary_interface_mac=$(cat "/sys/class/net/${primary_interface}/address")
is_controller=no
controller_address=""
if [ -z "${controller_mac}" ] || [ "${controller_mac}" = "${primary_interface_mac}" ]; then 
    is_controller=yes
fi

if [ "${is_controller}" == "yes" ]; then
    echo "Setting up controller"
    
    # SSH certificate
    ssh-keygen -s /CAssh/ca_host_key -n "$(hostname)" -I ansible_cert -V +1d -h /etc/ssh/ssh_host_rsa_key.pub
    echo "HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub" >> /etc/ssh/sshd_config
    cp -f /CAssh/ca_user_key.pub /etc/ssh/ca_user_key.pub
    echo "TrustedUserCAKeys /etc/ssh/ca_user_key.pub" >> /etc/ssh/sshd_config

    # Inventory for controller
    wget --header "Authorization: token ${param_token}" -O inventory.yml.tpl2 "${param_bootstrapurl}/files/seo/inventories/controller.yml"
    # shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
    envsubst '$flavor' < inventory.yml.tpl2 > inventory.yml.tpl
    rm -rf ./inventory.yml.tpl2
else
    echo "Setting up node"

    echo "Trying to obtain controller's IP using its MAC"
    while [ -z "${controller_address}" ]; do
        controller_address=$(arp-scan -q --localnet --destaddr="${controller_mac}" -I "${primary_interface}" | grep "${controller_mac}" | head -n1 | awk '{print $1}')
    done
    echo "Found controller: ${controller_address}"
    export controller_address
    
    # SSH certificate
    ssh-keygen -s /CAssh/ca_user_key -I ansible_user -n root -V +1d ~/.ssh/id_rsa.pub
    echo "@cert-authority * $(cat /CAssh/ca_host_key.pub)" >> ~/.ssh/known_hosts

    # Inventory for node
    wget --header "Authorization: token ${param_token}" -O inventory.yml.tpl2 "${param_bootstrapurl}/files/seo/inventories/node.yml"
    # shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
    envsubst '$controller_address,$flavor' < inventory.yml.tpl2 > inventory.yml.tpl
    rm -rf ./inventory.yml.tpl2
fi

