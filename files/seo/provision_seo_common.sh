#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

set -euo pipefail
set -x

# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}

# (re)load settings - bash's associative arrays cannot be exported
# shellcheck source=./files/seo/provision_settings
source <(wget --header "Authorization: token ${param_token}" -O- "${param_bootstrapurl}/files/seo/provision_settings")

# shellcheck disable=SC2269 # variable origin: provision_settings
ek_path=${ek_path}
# shellcheck disable=SC2269 # variable origin: provision_settings
branch=${branch}
# shellcheck disable=SC2269 # pvariable origin: rovision_settings
url=${url}

# Generate SSH key
ssh-keygen -t rsa -q -f "$HOME/.ssh/id_rsa" -N "" <<< y
touch "$HOME/.ssh/authorized_keys"
cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"

# Install pipenv
python3 -m pip install pipenv
echo "export PATH=${HOME}/.local/bin:$PATH" >> ~/.bashrc
export PATH=${HOME}/.local/bin:$PATH

# Systemd service
wget --header "Authorization: token ${param_token}" -O /tmp/seo_deploy.sh.tpl "${param_bootstrapurl}/files/seo/systemd/seo_deploy.sh"
wget --header "Authorization: token ${param_token}" -O /tmp/seo.service.tpl "${param_bootstrapurl}/files/seo/systemd/seo.service"
envsubst < /tmp/seo.service.tpl > /etc/systemd/system/seo.service
# shellcheck disable=SC2016 # envsubst needs the environment variables unexpanded
envsubst '$ek_path' < /tmp/seo_deploy.sh.tpl > /usr/bin/seo_deploy.sh
rm -rf /tmp/seo.service.tpl /tmp/seo_deploy.sh.tpl
systemctl enable seo

# Clone Experience Kit
rm -rf "${ek_path}"
if [ -n "${gh_token}" ]; then
    git config --global url."https://${gh_token}@github.com".insteadOf https://github.com
fi
git clone --branch "${branch}" --recursive "https://${url}" "${ek_path}"
if [ -n "${gh_token}" ]; then
    git config --global --remove-section url."https://${gh_token}@github.com"
fi
cd "${ek_path}"


# shellcheck disable=SC2154
for remote_filename in "${!files[@]}"; do
    dest_path=${files[$remote_filename]}
    if [[ "${dest_path}" == */ ]]; then
        # dest_path ends with / - filename will be added to the path
        dest_path="${dest_path}${remote_filename}"
    fi

    dest_dir=$(dirname "${dest_path}")
    mkdir -p "${dest_dir}"

    # if starts with / then path is absolute
    if [[ "${dest_path:0:1}" == '/' ]]; then
        echo "${remote_filename} will be copied to ${dest_path}"
    else
        echo "${remote_filename} will be copied to ${ek_path}/${dest_path}"
    fi

    wget --header "Authorization: token ${param_token}" -O "${dest_path}" "${param_bootstrapurl}/files/seo/sideload/${remote_filename}"
done

# Install Python packages
make install-dependencies

# Get group_var and host_vars
mkdir -p inventory/default/group_vars/{all,controller_group,edgenode_group} inventory/default/host_vars/{controller,node01}
wget --header "Authorization: token ${param_token}" -O inventory/default/group_vars/all/90-settings.yml "${param_bootstrapurl}/files/seo/group_vars/all.yml"
wget --header "Authorization: token ${param_token}" -O inventory/default/group_vars/controller_group/90-settings.yml "${param_bootstrapurl}/files/seo/group_vars/controller_group.yml"
wget --header "Authorization: token ${param_token}" -O inventory/default/group_vars/edgenode_group/90-settings.yml "${param_bootstrapurl}/files/seo/group_vars/edgenode_group.yml"
wget --header "Authorization: token ${param_token}" -O inventory/default/host_vars/controller/90-settings.yml "${param_bootstrapurl}/files/seo/host_vars/controller.yml"
wget --header "Authorization: token ${param_token}" -O inventory/default/host_vars/node01/90-settings.yml "${param_bootstrapurl}/files/seo/host_vars/node01.yml"
