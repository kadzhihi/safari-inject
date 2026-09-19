#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdarg.h>

// This is the only ElleKit-injected dylib.  It deliberately leaves all WebKit
// and HTTP work to the payload after MobileSafari's main run loop is alive.
typedef void (*ICHTPayloadStartFn)(void);
static NSString * const ICHTStatusPrefix = @"IOSCONTROL_SAFARI_";

static void ICHTBootstrapLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

static void ICHTBootstrapLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[IOSControlSafariBootstrap] %@", message);
}

// The existing IOSControl runtime test can safely inspect this lightweight
// diagnostic marker.  It is informational only; /ping remains the pass/fail
// criterion and no UIKit work happens in the constructor path.
static void ICHTSetBootstrapStatus(NSString *status) {
    if (![status isKindOfClass:NSString.class]) return;
    void (^publish)(void) = ^{
        NSString *value = [ICHTStatusPrefix stringByAppendingString:status];
        [UIPasteboard generalPasteboard].string = value;
        ICHTBootstrapLog(@"%@", value);
    };
    if (NSThread.isMainThread) publish();
    else dispatch_async(dispatch_get_main_queue(), publish);
}

static BOOL ICHTIsMobileSafari(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    NSString *process = NSProcessInfo.processInfo.processName;
    return [bundle isEqualToString:@"com.apple.mobilesafari"] &&
           [process isEqualToString:@"MobileSafari"];
}

static void ICHTLoadPayload(void) {
    static dispatch_once_t loadOnce;
    dispatch_once(&loadOnce, ^{
        @autoreleasepool {
            NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
            NSString *process = NSProcessInfo.processInfo.processName ?: @"unknown";
            if (!ICHTIsMobileSafari()) {
                ICHTSetBootstrapStatus([NSString stringWithFormat:@"PAYLOAD_NOT_LOADED process=%@ bundle=%@", process, bundle]);
                return;
            }

            const char *paths[] = {
                "/var/jb/usr/lib/TweakInject/IOSControlSafariPayload.dylib",
                "/var/jb/Library/MobileSubstrate/DynamicLibraries/IOSControlSafariPayload.dylib",
            };
            void *handle = NULL;
            NSString *lastError = nil;
            for (NSUInteger index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
                dlerror();
                handle = dlopen(paths[index], RTLD_NOW | RTLD_LOCAL);
                if (handle) {
                    ICHTSetBootstrapStatus([NSString stringWithFormat:@"PAYLOAD_DLOPEN_OK path=%s", paths[index]]);
                    break;
                }
                const char *error = dlerror();
                lastError = error ? [NSString stringWithUTF8String:error] : @"unknown dlerror";
                ICHTSetBootstrapStatus([NSString stringWithFormat:@"PAYLOAD_DLOPEN_FAIL path=%s error=%@", paths[index], lastError]);
            }
            if (!handle) return;

            dlerror();
            ICHTPayloadStartFn start = (ICHTPayloadStartFn)dlsym(handle, "ICHTPayloadStart");
            const char *symbolError = dlerror();
            if (!start || symbolError) {
                ICHTSetBootstrapStatus([NSString stringWithFormat:@"PAYLOAD_DLSYM_FAIL error=%@",
                                        symbolError ? [NSString stringWithUTF8String:symbolError] : @"ICHTPayloadStart missing"]);
                return;
            }

            // The payload owns Objective-C classes, so its dlopen handle must live
            // for the rest of MobileSafari's process lifetime.
            start();
            ICHTSetBootstrapStatus(@"PAYLOAD_START_CALLED");
        }
    });
}

%ctor {
    @autoreleasepool {
        if (!ICHTIsMobileSafari()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1500 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            ICHTLoadPayload();
        });
    }
}
