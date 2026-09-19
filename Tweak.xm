#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import "Diagnostics.h"
#import "HTTPServer.h"

static NSString *ICHTClipboardMarker(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"nil";
    return [NSString stringWithFormat:
        @"IOSCONTROL_SAFARI_CTOR_OK|pid=%d|bundle=%@|timestamp=%.3f",
        (int)getpid(),
        bundle,
        [NSDate date].timeIntervalSince1970
    ];
}

%ctor {
    @autoreleasepool {
        ICHTLog(@"[CTOR] loaded %@", ICHTProcessInfo());

        /*
         * Primary injection proof used by IOSControl.
         * This deliberately does not depend on Safari's sandbox filesystem.
         * The IOSControl test clears the pasteboard before launching Safari,
         * then polls clipText() for this exact prefix.
         */
        NSString *clipboardMarker = ICHTClipboardMarker();
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = clipboardMarker;
        ICHTLog(@"[CTOR] clipboard marker set: %@", clipboardMarker);

        /* Keep the existing diagnostics as secondary evidence. */
        NSString *markerPath = @"/var/mobile/Library/IOSControl/Scripts/safari_ctor_marker.txt";
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"nil";
        NSString *marker = [NSString stringWithFormat:
            @"IOSCONTROL_SAFARI_CTOR_OK\npid=%d\nbundle=%@\n",
            (int)getpid(),
            bundle
        ];
        NSError *markerError = nil;
        BOOL markerWritten = [marker writeToFile:markerPath
                                       atomically:YES
                                         encoding:NSUTF8StringEncoding
                                            error:&markerError];
        NSLog(@"[IOSControlSafariHTTP][CTOR] marker=%d error=%@",
              markerWritten ? 1 : 0,
              markerError);

        ICHTWriteInjectionMarker();

        ICHTLog(@"[CTOR] starting HTTP server");
        [[ICHTHTTPServer sharedServer] start];
        ICHTLog(@"[CTOR] HTTP server start requested");
    }
}
