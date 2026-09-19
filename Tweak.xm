#import <Foundation/Foundation.h>
#import <unistd.h>
#import "Diagnostics.h"
#import "HTTPServer.h"

%ctor {
    @autoreleasepool {
        ICHTLog(@"[CTOR] loaded %@", ICHTProcessInfo());
        NSString *markerPath = @"/var/mobile/Library/IOSControl/Scripts/safari_ctor_marker.txt";
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"nil";
        NSString *marker = [NSString stringWithFormat:@"IOSCONTROL_SAFARI_CTOR_OK\npid=%d\nbundle=%@\n", (int)getpid(), bundle];
        NSError *markerError = nil;
        BOOL markerWritten = [marker writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:&markerError];
        NSLog(@"[IOSControlSafariHTTP][CTOR] marker=%d error=%@", markerWritten ? 1 : 0, markerError);
        ICHTWriteInjectionMarker();
        [[ICHTHTTPServer sharedServer] start];
    }
}
