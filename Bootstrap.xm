#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void (*ICHTRuntimeStatusCallback)(const char *message);
typedef BOOL (*ICHTPayloadStartFn)(ICHTRuntimeStatusCallback callback);

static NSString * const ICHTStatusPrefix = @"IOSCONTROL_SAFARI_";

static void ICHTSetPasteboardStatus(NSString *status) {
    if (![status isKindOfClass:NSString.class]) return;
    void (^writeBlock)(void) = ^{
        @autoreleasepool {
            NSString *value = [ICHTStatusPrefix stringByAppendingString:status];
            [UIPasteboard generalPasteboard].string = value;
            NSLog(@"[IOSControlSafariBootstrap] %@", value);
        }
    };

    if (NSThread.isMainThread) writeBlock();
    else dispatch_async(dispatch_get_main_queue(), writeBlock);
}

static void ICHTRuntimeStatusFromPayload(const char *message) {
    if (!message) return;
    NSString *status = [NSString stringWithUTF8String:message];
    if (status.length) ICHTSetPasteboardStatus(status);
}

static NSString *ICHTDLErrorString(void) {
    const char *error = dlerror();
    if (!error) return @"unknown dlerror";
    NSString *value = [NSString stringWithUTF8String:error];
    return value.length ? value : @"unknown dlerror";
}

static void ICHTLoadPayload(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"nil";
        NSString *process = NSProcessInfo.processInfo.processName ?: @"nil";

        ICHTSetPasteboardStatus([NSString stringWithFormat:
            @"BOOTSTRAP_LOADED|pid=%d|process=%@|bundle=%@",
            (int)getpid(), process, bundle]);

        if (![bundle isEqualToString:@"com.apple.mobilesafari"] &&
            ![process isEqualToString:@"MobileSafari"]) {
            ICHTSetPasteboardStatus([NSString stringWithFormat:
                @"BOOTSTRAP_WRONG_PROCESS|process=%@|bundle=%@", process, bundle]);
            return;
        }

        const char *paths[] = {
            "/var/jb/usr/lib/TweakInject/IOSControlSafariPayload.dylib",
            "/var/jb/Library/MobileSubstrate/DynamicLibraries/IOSControlSafariPayload.dylib"
        };

        void *handle = NULL;
        NSString *usedPath = nil;
        NSString *lastError = nil;

        for (NSUInteger i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
            dlerror();
            handle = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
            if (handle) {
                usedPath = [NSString stringWithUTF8String:paths[i]];
                break;
            }
            lastError = ICHTDLErrorString();
        }

        if (!handle) {
            ICHTSetPasteboardStatus([NSString stringWithFormat:
                @"PAYLOAD_DLOPEN_FAIL|error=%@", lastError ?: @"unknown"]);
            return;
        }

        ICHTSetPasteboardStatus([NSString stringWithFormat:
            @"PAYLOAD_DLOPEN_OK|path=%@", usedPath ?: @"unknown"]);

        dlerror();
        ICHTPayloadStartFn startFn =
            (ICHTPayloadStartFn)dlsym(handle, "ICHTPayloadStart");
        const char *symbolError = dlerror();

        if (!startFn || symbolError) {
            NSString *error = symbolError ?
                ([NSString stringWithUTF8String:symbolError] ?: @"unknown dlsym error") :
                @"ICHTPayloadStart missing";
            ICHTSetPasteboardStatus([NSString stringWithFormat:
                @"PAYLOAD_DLSYM_FAIL|error=%@", error]);
            return;
        }

        BOOL started = startFn(ICHTRuntimeStatusFromPayload);
        if (!started) {
            ICHTSetPasteboardStatus(@"PAYLOAD_START_RETURNED_FALSE");
            return;
        }

        // HTTPServer will replace this with HTTP_LISTENING or an exact socket error.
        ICHTSetPasteboardStatus(@"PAYLOAD_START_CALLED");
    }
}

%ctor {
    @autoreleasepool {
        // Do almost nothing under dyld/ElleKit's load path. Safari/UI work is delayed
        // until its main run loop is alive, avoiding constructor-time UIKit/WebKit work.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ICHTLoadPayload();
        });
    }
}
