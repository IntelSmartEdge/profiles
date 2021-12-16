#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2019-2021 Intel Corporation

set -e

MY_NAME=$(basename "$0")

# shellcheck disable=SC2251,SC2162
! read -d '' usage <<EOF
Usage: ${MY_NAME} [-h] [-d DEVICE]

  Partition a block device to match the Smart Edge Open expectations. The device is selected automatically unless the
  -d option is used.

  WARNING: Be sure that you know what you do. This script may wipe out your machine's disk if used incorrectly.

  -h        Display this message
  -d DEVICE The block DEVICE to partition.
EOF

DEVICE=''

while getopts "hd:" CURR_OPT; do
    case $CURR_OPT in
        h) echo "$usage"; exit 0;;
        d) DEVICE=$OPTARG;;
        *) echo "${MY_NAME}: ERROR: Unrecognized option. You can use the -h option to see the help message"; exit 1;;
    esac
done

if [ -z "$DEVICE" ]; then
    echo "INFO: The target device was not specified and will be selected automatically" 2>&1 | tee -a /dev/console
    # shellcheck disable=SC2144
    if [[ $(ls -l /sys/block/nvme[0-9]n[0-9] 2>/dev/null) ]]; then
        # shellcheck disable=SC2010
        DRIVE="/dev/$(ls -l /sys/block/nvme* | grep -v usb | head -n1 | sed 's/^.*\(nvme[a-z0-1]\+\).*$/\1/')"
        export DRIVE
        export BOOT_PARTITION=${DRIVE}p1
        export ROOT_PARTITION=${DRIVE}p2
    elif [[ $(ls -l /sys/block/[vsh]d[a-z] 2>/dev/null) ]]; then
        # shellcheck disable=SC2010
        DRIVE="/dev/$(ls -l /sys/block/[vsh]d[a-z] | grep -v usb | head -n1 | sed 's/^.*\([vsh]d[a-z]\+\).*$/\1/')"
        export DRIVE
        export BOOT_PARTITION=${DRIVE}1
        export ROOT_PARTITION=${DRIVE}2
    elif [[ $(ls -l /sys/block/mmcblk[0-9] 2>/dev/null) ]]; then
        # shellcheck disable=SC2010
        DRIVE="/dev/$(ls -l /sys/block/mmcblk[0-9] | grep -v usb | head -n1 | sed 's/^.*\(mmcblk[0-9]\+\).*$/\1/')"
        export DRIVE
        export BOOT_PARTITION=${DRIVE}p1
        export ROOT_PARTITION=${DRIVE}p2
    else
        echo "No supported drives found!" 2>&1 | tee -a /dev/console
        sleep 300
        reboot
    fi
else
    echo "INFO: The target device was specified through the '-d' command line argument" 2>&1 | tee -a /dev/console
    case "${DEVICE}" in
        /dev/[vhs]d[a-z])
            # shellcheck disable=SC2010,SC2086
            DRIVE="/dev/$(ls -l /sys/block/[vsh]d[a-z] | grep -v usb | head -n1 | sed 's/^.*\([vsh]d[a-z]\+\).*$/\1/' | grep ${DEVICE##/*/})"
            export DRIVE
            export BOOT_PARTITION=${DRIVE}1
            export ROOT_PARTITION=${DRIVE}2 ;;
        /dev/nvme)
            # shellcheck disable=SC2010,SC2086
            DRIVE="/dev/$(ls -l /sys/block/nvme* | grep -v usb | head -n1 | sed 's/^.*\(nvme[a-z0-1]\+\).*$/\1/' | grep ${DEVICE##/*/})"
            export DRIVE
            export BOOT_PARTITION=${DRIVE}p1
            export ROOT_PARTITION=${DRIVE}p2 ;;
        /dev/mmcblk)
            # shellcheck disable=SC2010,SC2086
            DRIVE="/dev/$(ls -l /sys/block/mmcblk[0-9] | grep -v usb | head -n1 | sed 's/^.*\(mmcblk[0-9]\+\).*$/\1/' | grep ${DEVICE##/*/})"
            export DRIVE
            export BOOT_PARTITION=${DRIVE}p1
            export ROOT_PARTITION=${DRIVE}p2 ;;
        *)
            echo "Unsupported drive specified!" 2>&1 | tee -a /dev/console
            exit 1
    esac
    if [[ "$DRIVE" != "$DEVICE" ]]; then
        echo "${DEVICE} not found!" 2>&1 | tee -a /dev/console
        exit 1
    fi
fi

# Define a minimal replacement of the 'run' function if it is not defined. In the ESP/uOS environment it is provided by
# the ESP bootstraping scripts. The replacement definition is needed to run the script stand-alone:
if [ "$(type -t run)" != 'function' ]; then
    echo "INFO: The 'run' function is not defined"
    run() {
        local msg=$1
        local runThis=$2
        echo "$msg"
        unbuffer "$runThis"
    }
fi

# --- Create Volume Group/Name ---
VOLUME_GROUP="system-vg"
LOGICAL_VOLUME="root-lv"

# --- Create Boot/Root targets ---
export BOOTFS=/target/boot
export ROOTFS=/target/root
mkdir -p $BOOTFS
mkdir -p $ROOTFS

echo "" 2>&1 | tee -a /dev/console
echo "" 2>&1 | tee -a /dev/console
echo "Installing on ${DRIVE}" 2>&1 | tee -a /dev/console
echo "" 2>&1 | tee -a /dev/console
echo "" 2>&1 | tee -a /dev/console

# shellcheck disable=SC2269 # variable origin: pre.sh
param_parttype=${param_parttype}
# shellcheck disable=SC2269 # variable origin: pre.sh
param_validationmode=${param_validationmode}

# --- Partition HDD ---
run "Partitioning drive ${DRIVE}" \
    "if [[ $param_parttype == 'efi' ]]; then
        parted --script ${DRIVE} \
        mklabel gpt \
        mkpart ESP fat32 1MiB 807MiB \
        set 1 esp on \
        mkpart primary 807MiB 100% \
        set 2 lvm on;
    else
        parted --script ${DRIVE} \
        mklabel msdos \
        mkpart primary ext4 1MiB 550MiB \
        set 1 boot on \
        mkpart primary 551MiB 100% \
        set 2 lvm on;
    fi" \
    "${PROVISION_LOG}"

# --- Create Physical Volume ---
run "Creating Physical Volume on ${ROOT_PARTITION}" \
    "pvcreate -ff --yes ${ROOT_PARTITION}" \
    "${PROVISION_LOG}"

# --- Create Volume Group ---
run "Creating Volume Group on ${ROOT_PARTITION}" \
    "vgcreate ${VOLUME_GROUP} ${ROOT_PARTITION}" \
    "${PROVISION_LOG}"

# --- Create Logical Volume ---
# shellcheck disable=SC2086
diskspace=$(parted ${DRIVE} unit GiB print | grep 'Disk /' | awk '{ print $3 }')
diskspace=${diskspace::-3}
threshold=500
if [[ $param_validationmode == true ]] && [[ $diskspace -gt $threshold ]]; then
    run "Creating Logical Volume on ${VOLUME_GROUP}" \
        "lvcreate --yes -l +50%FREE ${VOLUME_GROUP} -n ${LOGICAL_VOLUME}" \
        "${PROVISION_LOG}"
else
    run "Creating Logical Volume on ${VOLUME_GROUP}" \
        "lvcreate --yes -l 100%FREE ${VOLUME_GROUP} -n ${LOGICAL_VOLUME}" \
        "${PROVISION_LOG}"
fi

# --- Create file systems ---
if [[ $param_parttype == 'efi' ]]; then
    run "Creating boot partition on drive ${DRIVE}" \
        "mkfs -t vfat -n BOOT ${BOOT_PARTITION} && \
        mkdir -p $BOOTFS && \
        mount ${BOOT_PARTITION} $BOOTFS" \
        "${PROVISION_LOG}"
else
    run "Creating boot partition on drive ${DRIVE}" \
        "mkfs -t ext4 -L BOOT -F ${BOOT_PARTITION} && \
        e2label ${BOOT_PARTITION} BOOT && \
        mkdir -p $BOOTFS && \
        mount ${BOOT_PARTITION} $BOOTFS" \
        "${PROVISION_LOG}"
fi

# --- Create ROOT file system ---
export ROOT_PARTITION=/dev/${VOLUME_GROUP}/${LOGICAL_VOLUME}
run "Creating root file system" \
    "mkfs -t ext4 ${ROOT_PARTITION} && \
    mount ${ROOT_PARTITION} $ROOTFS && \
    e2label ${ROOT_PARTITION} STATE_PARTITION" \
    "${PROVISION_LOG}"
