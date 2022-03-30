#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

set -euo pipefail
set -x

# shellcheck disable=SC2269 # variable origin: pre.sh
param_username=${param_username}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bare_os=${param_bare_os}

# Set up non-root user
echo "${param_username} ALL=(ALL) NOPASSWD:ALL" | tee "/etc/sudoers.d/${param_username}"
mkdir "/home/${param_username}/.ssh"
ssh-keygen -t rsa -f "/home/${param_username}/.ssh/id_rsa" -N "" -C "${param_username}"
cat /root/.ssh/id_rsa.pub >> "/home/${param_username}/.ssh/authorized_keys"

# Skip installing Experience Kit
if [ "${param_bare_os}" == "true" ]; then
    exit 0
fi

# shellcheck disable=SC2269 # variable origin: provision_settings
ek_path=${ek_path}
# shellcheck disable=SC2269 # variable origin: provision_settings
deployment=${deployment}

# Get inventory for single node
wget --header "Authorization: token ${param_token}" -O "${ek_path}/inventory.yml.tpl2" "${param_bootstrapurl}/files/seo/inventories/single_node.yml"
# shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
envsubst '$deployment $param_username' < "${ek_path}/inventory.yml.tpl2" > "${ek_path}/inventory.yml.tpl"
rm -rf "${ek_path}/inventory.yml.tpl2"
