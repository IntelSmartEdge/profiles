#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

set -x
set -euo pipefail

# shellcheck disable=SC2154
ek_dir="$ek_path"
marker_filename="${ek_dir}/.deployed"
issue_files=(/etc/issue /etc/issue.net)

clear_status() {
  # Remove old info from /etc/issue{,.net}
  for f in "${issue_files[@]}"; do
    sed '/Smart Edge Open Deployment Status/d' -i "${f}" >/dev/null
    printf "%s\n" "$(< "${f}")" > "${f}" # Remove redundant newlines at the end of file
  done
}

set_status() {
  local deploy_status=$1
  for f in "${issue_files[@]}"; do
    echo -e "\nSmart Edge Open Deployment Status: ${deploy_status}\n" >> "${f}"
  done
}

pushd "${ek_dir}"

clear_status

if [ -f "${marker_filename}" ]; then
  echo "SE already deployed (marker file detected)"
  set_status "deployed"
  exit 0
fi

# get the IP and insert it into inventory
IP=$(ip route get 8.8.8.8 | awk '{print $7}')
export IP
envsubst < inventory.yml.tpl > inventory.yml

export NO_PROXY="$NO_PROXY,$IP"
export no_proxy="$NO_PROXY"

set_status "in progress"
/root/.local/bin/pipenv install

set +e
/root/.local/bin/pipenv run ./deploy.py
status=$?
set -e

clear_status
if [ $status -eq 0 ]; then
  echo "SE deployed successfuly - creating marker"
  set_status "deployed"
  touch "${marker_filename}"
else
  set_status "failed. Check logs in ${ek_dir}/logs. To restart deployment run: systemctl restart seo"
fi

exit ${status}
