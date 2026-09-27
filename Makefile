ARCHS = arm64
TARGET = iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChickenGunTweak
ChickenGunTweak_FILES = Tweak.xm
ChickenGunTweak_CFLAGS = -fobjc-arc
ChickenGunTweak_CFLAGS = -I$(THEOS)/vendor/include

include $(THEOS_MAKE_PATH)/tweak.mk
