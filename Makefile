ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_ARCH = iphoneos-arm64
INSTALL_TARGET_PROCESSES = MobileSafari

TWEAK_NAME = IOSControlSafariHTTP
IOSControlSafariHTTP_FILES = Tweak.xm Diagnostics.m HTTPServer.m SafariPageFinder.m JavaScriptEvaluator.m
IOSControlSafariHTTP_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
IOSControlSafariHTTP_FRAMEWORKS = Foundation UIKit WebKit

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
