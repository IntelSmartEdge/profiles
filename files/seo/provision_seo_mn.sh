#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

set -euo pipefail
set -x

# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bare_os=${param_bare_os}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_username=${param_username}

# shellcheck disable=SC2269 # variable origin: profile.sh
is_controller=${is_controller}
# shellcheck disable=SC2269 # variable origin: profile.sh
primary_interface=${primary_interface}

# shellcheck disable=SC2269 # variable origin: provision_settings
controller_mac=${controller_mac}
# shellcheck disable=SC2269 # variable origin: provision_settings
ek_path=${ek_path}
# shellcheck disable=SC2269 # variable origin: provision_settings
deployment=${deployment}

# Add non-root user to sudoers
echo "${param_username} ALL=(ALL) NOPASSWD:ALL" | tee "/etc/sudoers.d/${param_username}"

cd "${ek_path}"

# Determine if machine is controlplane
cert_path=/CAssh
prefix="node"
if [ "${is_controller}" == "yes" ]; then
    prefix="cplane"
fi

### SSH Certificates

# Sign existing /etc/ssh/ssh_host_rsa_key.pub public key with our CA.
# This will create /etc/ssh/ssh_host_rsa_key-cert.pub
ssh-keygen -I "${prefix}_host" -s "${cert_path}/ca_key" -V -1h:+1w -h /etc/ssh/ssh_host_rsa_key.pub

# Set /etc/ssh/ssh_host_rsa_key-cert.pub as a certificate that SSHD will show to SSH clients
echo "HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub" >> /etc/ssh/sshd_config

# Configure host to trust clients with certs signed with ca_key.pub
cp "${cert_path}/ca_key.pub" /etc/ssh/ca_key.pub
echo "TrustedUserCAKeys /etc/ssh/ca_key.pub" >> /etc/ssh/sshd_config

# Sign root's public key with CA to be able to SSH to $param_username account
# This will result in creation of /root/.ssh/id_rsa-cert.pub
ssh-keygen -I "${prefix}_root" -s "${cert_path}/ca_key" -n "${param_username}" -V -1h:+1w /root/.ssh/id_rsa.pub

# Let's make root trust certs signed with our CA key
echo "@cert-authority * $(cat /etc/ssh/ca_key.pub)" >> /root/.ssh/known_hosts

###

# Skip installing Experience Kit
if [ "${param_bare_os}" == "true" ]; then
    exit 0
fi

if [ "${is_controller}" == "yes" ]; then
    echo "Setting up controller"

    # Inventory for controller
    wget --header "Authorization: token ${param_token}" -O inventory.yml.tpl2 "${param_bootstrapurl}/files/seo/inventories/controller.yml"
    # shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
    envsubst '$deployment,$param_username' < inventory.yml.tpl2 > inventory.yml.tpl

    rm -rf ./inventory.yml.tpl2
else
    echo "Setting up node"

    echo "Trying to obtain controller's IP using its MAC"
    controller_address=""
    while [ -z "${controller_address}" ]; do
        controller_address=$(arp-scan -q --localnet --destaddr="${controller_mac}" -I "${primary_interface}" | grep "${controller_mac}" | head -n1 | awk '{print $1}')
    done
    echo "Found controller: ${controller_address}"
    export controller_address

    # Inventory for node
    wget --header "Authorization: token ${param_token}" -O inventory.yml.tpl2 "${param_bootstrapurl}/files/seo/inventories/node.yml"
    # shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
    envsubst '$controller_address,$deployment,$param_username' < inventory.yml.tpl2 > inventory.yml.tpl

    rm -rf ./inventory.yml.tpl2
fi

