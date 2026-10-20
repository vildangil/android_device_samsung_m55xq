#
# Copyright (C) 2024 The Android Open Source Project
# Copyright (C) 2024 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/samsung/m55xq

# AERA 16.0 minimal manifest support
ALLOW_MISSING_DEPENDENCIES := true
# Known AERA 16.0 minimal-recovery Soong allowances (matches upstream
# AERA OnePlus 8 Pro bring-up; scope is this isolated port branch).
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_NINJA_USES_ENV_VARS += RTIC_MPGEN
BUILD_BROKEN_PLUGIN_VALIDATION := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 := 
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := kryo300

# Additional
TARGET_USES_UEFI := true
TARGET_IS_64_BIT := true
TARGET_USES_64_BIT_BINDER := true # For android-12.1 and below
TARGET_BOARD_SUFFIX := _64
TARGET_NO_BOOTLOADER := true

# Board
BOARD_USES_QCOM_HARDWARE := true
BOARD_NO_RADIOIMAGE := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_SUPPRESS_SECURE_ERASE := true

# Bootloader
BOARD_VENDOR := samsung
TARGET_SOC := taro
TARGET_BOOTLOADER_BOARD_NAME := $(TARGET_SOC)
TARGET_BOARD_PLATFORM := $(TARGET_SOC)
QCOM_BOARD_PLATFORMS := $(TARGET_SOC)
TARGET_BOARD_PLATFORM_GPU := Adreno-730

# Display
AERA_THEME := portrait_hdpi
TARGET_SCREEN_DENSITY := 403
TARGET_SCREEN_HEIGHT := 1080
TARGET_SCREEN_WIDTH := 2340
AERA_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
AERA_MAX_BRIGHTNESS := 500
AERA_DEFAULT_BRIGHTNESS := 255
AERA_FRAMERATE := 120
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

# Status Bar UI
AERA_STATUS_ICONS_ALIGN := center
AERA_CUSTOM_CPU_POS := "50"
AERA_CUSTOM_CLOCK_POS := "300"
AERA_CUSTOM_BATTERY_POS := "750"

# Cmdline
BOARD_KERNEL_CMDLINE :=  \
	video=vfb:640x400,bpp=32,memsize=3072000 \
	printk.devkmsg=on \
	firmware_class.path=/vendor/firmware_mnt/image \
	console=null \
	bootconfig \
	androidboot.hardware=qcom \
	hardware=qcom \
	androidboot.memcg=1 \
	androidboot.usbcontroller=a600000.dwc3 \
	androidboot.init_fatal_panic=true \
	androidboot.selinux=permissive \
	loop.max_part=7

# Kernel
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096

# Kernel - prebuilt
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb.img
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

# mkbootimg
BOARD_MKBOOTIMG_ARGS:= \
--board=SRPWI19A003 \
--dtb_offset=0x01f00000 \
--kernel_offset=0x00008000 \
--ramdisk_offset=0x02000000 \
--tags_offset=0x01e00000 \
--header_version=$(BOARD_BOOTIMG_HEADER_VERSION) \
--dtb=$(TARGET_PREBUILT_DTB) 

# Partitions
BOARD_FLASH_BLOCK_SIZE := 262144 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_BOOTIMAGE_PARTITION_SIZE := 112070656
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 112070656

BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

BOARD_SUPER_PARTITION_SIZE := 9126805504 # TODO: Fix hardcoded value
BOARD_SUPER_PARTITION_GROUPS := samsung_dynamic_partitions
# The Galaxy M55/F55 super partition contains six distinct logical
# partitions. Repeating "system" here makes AERA/Android 16 fsgen reject
# the entire super image with "Duplicate partitions found".
BOARD_SAMSUNG_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product odm system_ext vendor_dlkm
BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE := 9122611200 # TODO: Fix hardcoded value

# Recovery
RECOVERY_SDCARD_ON_DATA := true
# AERA Wi-Fi UI and supplicant; the Qualcomm WLAN module is loaded on demand.
OF_ENABLE_WLAN := 1
TARGET_RECOVERY_QCOM_RTC_FIX := true
BOARD_INCLUDE_RECOVERY_DTBO := true
BOARD_KERNEL_SEPARATED_DTBO := true

# File System & Storage
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_HAS_LARGE_FILESYSTEM := true
AERA_SKIP_ADDITIONAL_FSTAB := true
AERA_USE_EXTERNAL_STORAGE := true
TARGET_USES_MKE2FS := true 
AERA_INCLUDE_NTFS_3G := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

# Verified Boot
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# Match the installed Android 16 system/vendor SPL during KeyMint startup.
# The artificial 2099 patch levels break KeyMint keyblob version validation.
PLATFORM_SECURITY_PATCH := 2025-12-01
VENDOR_SECURITY_PATCH := 2025-12-01
PLATFORM_VERSION := 16.1.0

# Encryption
# Stock Samsung Android 16 FBE/metadata encryption + hardware Weaver.
# Keep the known-working KeyMint SPL, ueventd and Hermes files intact.
AERA_INCLUDE_CRYPTO := true
AERA_INCLUDE_CRYPTO_FBE := true
AERA_USE_FSCRYPT_POLICY := 2
BOARD_USES_METADATA_PARTITION := true
AERA_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_QCOM_FBE_DECRYPTION := true

# USB
AERA_USE_NEW_MINADBD := true
AERA_EXCLUDE_DEFAULT_USB_INIT := true

# Misc
AERA_INCLUDE_REPACKTOOLS := true
AERA_EXTRA_LANGUAGES := true
AERA_INCLUDE_LPTOOLS := true
AERA_INCLUDE_LPDUMP := true

# AERA Recovery configuration
AERA_SCREEN_BLANK_ON_BOOT := true
AERA_INPUT_BLACKLIST := "hbtp_vm"
AERA_USE_TOOLBOX := true
AERA_EXCLUDE_APEX := true
AERA_NO_BIND_SYSTEM := true
AERA_PREPARE_DATA_MEDIA_EARLY := true
AERA_USE_MODEL_HARDWARE_ID_FOR_DEVICE_ID := true
AERA_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone50/temp"
# TWRP's legacy battery monitor appends /capacity and /status itself.
# Use sysfs directly: Samsung's recovery Health HAL reports NOT_SUPPORTED / 0%.
# Do not use a fake battery level.
AERA_USE_LEGACY_BATTERY_SERVICES := true
AERA_CUSTOM_BATTERY_PATH := "/sys/class/power_supply/battery"

# Samsung
AERA_NO_REBOOT_BOOTLOADER := true
AERA_USE_SAMSUNG_HAPTICS := true
AERA_INCLUDE_FASTBOOTD := true
AERA_HAS_DOWNLOAD_MODE := true

# Copy Out 
TARGET_COPY_OUT_VENDOR := vendor

# Logging
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TWRP_EVENT_LOGGING := true

# Properties
AERA_NO_LEGACY_PROPS := true
AERA_INCLUDE_LIBRESETPROP := true
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Treble
PRODUCT_ENFORCE_VINTF_MANIFEST := true
PRODUCT_FULL_TREBLE := true

# AERA bring-up identity
AERA_DEVICE_VERSION := VildanG
AERA_MAINTAINER := VildanG
AERA_UI_ADAPTIVE_RESOLUTION := true
AERA_ENABLE_ALL_PARTITION_TOOLS := true

# AERA 16.0 bring-up is experimental until tested on SM-M556B.
