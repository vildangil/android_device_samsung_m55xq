# Copyright (C) 2024 The Android Open Source Project
# SPDX-License-Identifier: Apache-2.0

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/twrp_m55xq.mk

# AERA 16.0 / Android 16 uses bp2a release-config lunch selectors.
COMMON_LUNCH_CHOICES := \
    twrp_m55xq-bp2a-eng \
    twrp_m55xq-bp2a-userdebug
