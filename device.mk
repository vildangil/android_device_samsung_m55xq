# Copyright (C) 2024 The Android Open Source Project
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := device/samsung/m55xq

# Preserve the proven TWRP device API/VNDK settings for the first AERA
# bring-up. Validate them on hardware before adjusting crypto semantics.
PRODUCT_SHIPPING_API_LEVEL := 30
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_TARGET_VNDK_VERSION := 32

# AERA 16.0 supplies the native recovery UI and OTA tools itself; avoid
# installing the old Android 12.1 otapreopt/update_engine packages here.
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-impl.recovery \
    android.hardware.health@2.1-service \
    qcom_decrypt \
    qcom_decrypt_fbe

# Keep ICU library linkage used by the proven Samsung encryption setup.
TARGET_RECOVERY_DEVICE_MODULES += libandroidicu
RECOVERY_LIBRARY_SOURCE_FILES += $(TARGET_OUT_SHARED_LIBRARIES)/libandroidicu.so

PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)
PRODUCT_PROPERTY_OVERRIDES += persist.sys.fuse.passthrough.enable=true
