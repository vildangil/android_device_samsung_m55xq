# Copyright (C) 2024 The Android Open Source Project
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0

# AERA Recovery 16.0 uses Android 16 base products. Do not inherit Android
# 12.1 full_base_telephony, and do not advertise the original synthetic
# Android 12 build fingerprint: stock KeyMint expects Android 16/SPL values.
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, device/samsung/m55xq/device.mk)

PRODUCT_DEVICE := m55xq
PRODUCT_NAME := twrp_m55xq
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-M556B
PRODUCT_MANUFACTURER := samsung
PRODUCT_RELEASE_NAME := m55xq
PRODUCT_GMS_CLIENTID_BASE := android-samsung

AERA_STATUS_ICONS_ALIGN := center
