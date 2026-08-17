ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DDDouyinParse

DDDouyinParse_FILES = DDDouyinParse.xm
DDDouyinParse_CFLAGS = -fobjc-arc
DDDouyinParse_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
