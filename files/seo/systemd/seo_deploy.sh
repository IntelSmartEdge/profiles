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
  # first clear previous status
  clear_status

  local deploy_status=$1
  for f in "${issue_files[@]}"; do
    echo -e "\nSmart Edge Open Deployment Status: ${deploy_status}\n" >> "${f}"
  done
}

# if user has intentionally restarted a previously successful deployment,
# remove marker for clarity
if [ -f "${marker_filename}" ]; then
  rm "${marker_filename}"
fi

pushd "${ek_dir}"

# get the IP and insert it into inventory
IP=$(ip route get 8.8.8.8 | awk '{print $7}')
export IP
envsubst < inventory.yml.tpl > inventory.yml

export NO_PROXY="$NO_PROXY,$IP"
export no_proxy="$NO_PROXY"

set_status "in progress"

set +e
./deploy.sh
status=$?
set -e

if [ $status -eq 0 ]; then
  echo "SE deployed successfuly"
  set_status "deployed"
  # put marker for clarity
  touch "${marker_filename}"
  # no need to run deploy ever again
  systemctl disable seo
else
  set_status "failed. Check logs in ${ek_dir}/logs. To restart deployment run: systemctl restart seo"
fi

exit ${status}
