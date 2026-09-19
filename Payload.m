#import "Payload.h"
#import "Diagnostics.h"
#import "HTTPServer.h"

__attribute__((visibility("default"))) void ICHTPayloadStart(void) {
    static dispatch_once_t startOnce;
    dispatch_once(&startOnce, ^{
        // HTTPServer moves its socket work to a serial queue. Starting it on main
        // preserves UIKit/WebKit thread affinity during payload initialization.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *info = ICHTProcessInfo();
            ICHTLog(@"[PAYLOAD] starting in process=%@ bundle=%@ arch=%@",
                    info[@"process"] ?: @"unknown", info[@"bundle"] ?: @"unknown",
                    info[@"architecture"] ?: @"unknown");
            [[ICHTHTTPServer sharedServer] start];
        });
    });
}
