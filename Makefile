# Rootless (palera1n rootless / Dopamine). Untuk jailbreak ROOTFUL (checkra1n,
# palera1n --rootful, unc0ver, Odyssey) hapus / comment baris di bawah ini.
export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidGlassCharge

LiquidGlassCharge_FILES = Tweak.x
LiquidGlassCharge_CFLAGS = -fobjc-arc
LiquidGlassCharge_FRAMEWORKS = UIKit QuartzCore CoreMotion

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
