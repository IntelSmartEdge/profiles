#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2019-2021 Intel Corporation

set -a

# this is provided while using uOS
# shellcheck source=/dev/null
source /opt/bootstrap/functions

param_httpserver=$1

# --- Get kernel parameters ---
kernel_params=$(cat /proc/cmdline)

if [[ $kernel_params == *"token="* ]]; then
    tmp="${kernel_params##*token=}"
    export param_token="${tmp%% *}"
fi

if [[ $kernel_params == *"bootstrap="* ]]; then
    tmp="${kernel_params##*bootstrap=}"
    export param_bootstrap="${tmp%% *}"
    export param_bootstrapurl=${param_bootstrap//$(basename "$param_bootstrap")/}
fi

# shellcheck source=pre.sh
source <(wget --header "Authorization: token ${param_token}" -O - "${param_bootstrapurl}/pre.sh") && \
wget --header "Authorization: token ${param_token}" -O - "${param_bootstrapurl}/profile.sh" | bash -s - "$param_httpserver" && \
wget --header "Authorization: token ${param_token}" -O - "${param_bootstrapurl}/post.sh" | bash -s - "$param_httpserver"
