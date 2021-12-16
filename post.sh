#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2019-2021 Intel Corporation

set -o pipefail

# this is provided while using uOS
# shellcheck source=/dev/null
source /opt/bootstrap/functions
PROVISIONER=$1

# shellcheck disable=SC2269 # variable origin: pre.sh
param_bootstrapurl=${param_bootstrapurl}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_token=${param_token}
# shellcheck source=./files/seo/provision_settings
source <(wget --header "Authorization: token ${param_token}" -O- "${param_bootstrapurl}/files/seo/provision_settings")
# shellcheck disable=SC2269 # variable origin: provision_settings
enable_secure_boot=${enable_secure_boot}
# shellcheck disable=SC2269 # variable origin: provision_settings
enable_tpm=${enable_tpm}
# shellcheck disable=SC2269 # variable origin: provision_settings
redfish_ip=${redfish_ip}
# shellcheck disable=SC2269 # variable origin: provision_settings
redfish_user=${redfish_user}
# shellcheck disable=SC2269 # variable origin: provision_settings
redfish_password=${redfish_password}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_parttype=${param_parttype}
# A proxy that has access to out of band management interface
management_proxy="http://${PROVISIONER}:3128/"

if [[ "${enable_secure_boot}" == "true" ]] && [[ $param_parttype == "efi" ]]; then
    run "Enabling secure boot" \
    "wget --header \"Authorization: token ${param_token}\" -O - \"${param_bootstrapurl}/redfish.py\" \
    | python3 - sb on --ip \"${redfish_ip}\" -u \"${redfish_user}\" -p \"${redfish_password}\" --proxy \"${management_proxy}\"" \
    "${PROVISION_LOG}"
fi

if [[ "${enable_tpm}" == "true" ]]; then
    run "Enabling trusted module platform" \
    "wget --header \"Authorization: token ${param_token}\" -O - \"${param_bootstrapurl}/redfish.py\" \
    | python3 - tpm on --ip \"${redfish_ip}\" -u \"${redfish_user}\" -p \"${redfish_password}\" --proxy \"${management_proxy}\"" \
    "${PROVISION_LOG}"
fi

stop=$(date +%s)
# shellcheck disable=SC2154 # $start defined in pre.sh
elapsed_total_seconds=$((stop - start))
elapsed_min=$((elapsed_total_seconds / 60))
elapsed_sec=$((elapsed_total_seconds % 60))

run "Finished. Elapsed time: ${elapsed_min} minutes ${elapsed_sec} seconds (total seconds: ${elapsed_total_seconds})" \
    "echo 'Finished. Elapsed time: ${elapsed_min} minutes ${elapsed_sec} seconds (total seconds: ${elapsed_total_seconds})'" \
    "${PROVISION_LOG}"

run "Provisioning log will be available in /var/log/provisioning.log" \
    "true" \
    "/dev/null"

cp "${PROVISION_LOG}" "$ROOTFS/var/log/provisioning.log"

# --- Cleanup ---
# shellcheck disable=SC2154 # $freemem defined in pre.sh
if [ "$freemem" -lt 6291456 ]; then
    run "Cleaning up" \
        "killall dockerd &&
        sleep 3 &&
        swapoff $ROOTFS/swap &&
        rm $ROOTFS/swap &&
        while (! rm -fr $ROOTFS/tmp/ > /dev/null ); do sleep 2; done" \
        "${PROVISION_LOG}"
fi

# shellcheck disable=SC2154 # $BOOTFS, $ROOTFS, and $param_diskencrypt defined in pre.sh
umount "$BOOTFS" &&
umount "$ROOTFS" &&
if [[ $param_diskencrypt == 'true' ]]; then
    cryptsetup luksClose root 2>&1 | tee -a /dev/console
fi

run "Rebooting in 10 seconds" \
    "sleep 10 && reboot" \
    "/dev/null"
