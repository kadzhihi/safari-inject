ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_ARCH = iphoneos-arm64
INSTALL_TARGET_PROCESSES = MobileSafari

include $(THEOS)/makefiles/common.mk

# Only this very small dylib is auto-injected by ElleKit.
# It waits until Safari has finished starting, then dlopen()s the heavy payload.
TWEAK_NAME = IOSControlSafariBootstrap IOSControlSafariPayload

IOSControlSafariBootstrap_FILES = Bootstrap.xm
IOSControlSafariBootstrap_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
IOSControlSafariBootstrap_FRAMEWORKS = Foundation UIKit

# The payload is deliberately NOT auto-injected. Its plist matches an impossible
# executable name. Bootstrap.xm loads it manually after MobileSafari startup.
IOSControlSafariPayload_FILES = Payload.m Diagnostics.m HTTPServer.m SafariPageFinder.m JavaScriptEvaluator.m
IOSControlSafariPayload_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
IOSControlSafariPayload_FRAMEWORKS = Foundation UIKit WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
