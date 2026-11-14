TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiquidChargePrefs
LiquidChargePrefs_FILES = LCRootListController.m
LiquidChargePrefs_FRAMEWORKS = UIKit
# Framework privat 'Preferences' tidak ada di SDK runner; kelasnya di-resolve saat runtime di app Settings
LiquidChargePrefs_LDFLAGS = -undefined dynamic_lookup
LiquidChargePrefs_INSTALL_PATH = /Library/PreferenceBundles
LiquidChargePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
