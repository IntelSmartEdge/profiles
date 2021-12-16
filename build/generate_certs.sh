#!/bin/sh

# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2021 Intel Corporation

apk update && apk add --no-cache openssh-keygen
mkdir -p /opt/embedded/certs
ssh-keygen -t rsa -f /opt/embedded/certs/ca_key -P ""
