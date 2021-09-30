#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2019-2021 Intel Corporation

# this is provided while using uOS
# shellcheck source=/dev/null
source /opt/bootstrap/functions

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
