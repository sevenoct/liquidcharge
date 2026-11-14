TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiquidGlassChargePrefs
LiquidGlassChargePrefs_FILES = LQRootListController.m
LiquidGlassChargePrefs_FRAMEWORKS = UIKit
# Framework privat 'Preferences' tidak ada di SDK runner; kelasnya di-resolve saat runtime di app Settings
LiquidGlassChargePrefs_LDFLAGS = -undefined dynamic_lookup
LiquidGlassChargePrefs_INSTALL_PATH = /Library/PreferenceBundles
LiquidGlassChargePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
