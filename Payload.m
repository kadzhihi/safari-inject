#import "Payload.h"
#import "Diagnostics.h"
#import "HTTPServer.h"

static ICHTRuntimeStatusCallback gRuntimeStatusCallback = NULL;
static BOOL gPayloadStarted = NO;

void ICHTReportRuntimeStatus(NSString *message) {
    if (![message isKindOfClass:NSString.class]) return;
    ICHTLog(@"[RUNTIME] %@", message);

    ICHTRuntimeStatusCallback callback = gRuntimeStatusCallback;
    if (!callback) return;

    const char *utf8 = message.UTF8String;
    if (utf8) callback(utf8);
}

__attribute__((visibility("default"))) BOOL
ICHTPayloadStart(ICHTRuntimeStatusCallback callback) {
    @autoreleasepool {
        if (callback) gRuntimeStatusCallback = callback;

        if (gPayloadStarted) {
            ICHTReportRuntimeStatus(@"PAYLOAD_ALREADY_STARTED");
            return YES;
        }
        gPayloadStarted = YES;

        NSDictionary *info = ICHTProcessInfo();
        NSString *bundle = info[@"bundle"] ?: @"unknown";
        NSString *process = info[@"process"] ?: @"unknown";
        NSString *architecture = info[@"architecture"] ?: @"unknown";
        ICHTReportRuntimeStatus([NSString stringWithFormat:
            @"PAYLOAD_START|process=%@|bundle=%@|arch=%@",
            process, bundle, architecture]);

        if (![bundle isEqualToString:@"com.apple.mobilesafari"] &&
            ![process isEqualToString:@"MobileSafari"]) {
            ICHTReportRuntimeStatus([NSString stringWithFormat:
                @"PAYLOAD_WRONG_PROCESS|process=%@|bundle=%@", process, bundle]);
            return NO;
        }

        [[ICHTHTTPServer sharedServer] start];
        return YES;
    }
}
