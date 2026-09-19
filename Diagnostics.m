#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#import <errno.h>
#import <string.h>

void ICHTLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[IOSControlSafariHTTP] %@", message);
}

NSString *ICHTErrno(void) {
    int e = errno;
    return [NSString stringWithFormat:@"errno=%d (%s)", e, strerror(e)];
}

NSDictionary *ICHTProcessInfo(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    return @{
        @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
        @"process": [NSProcessInfo processInfo].processName ?: @"unknown",
        @"bundle": bundle.bundleIdentifier ?: @"unknown",
#if __arm64e__
        @"architecture": @"arm64e"
#elif __arm64__
        @"architecture": @"arm64"
#else
        @"architecture": @"unknown"
#endif
    };
}

void ICHTWriteInjectionMarker(void) {
    NSDictionary *p = ICHTProcessInfo();
    NSString *marker = [NSString stringWithFormat:
        @"IOSCONTROL_SAFARI_LOADED\nprocess=%@\npid=%@\nbundle=%@\narchitecture=%@\ntimestamp=%@\n",
        p[@"process"], p[@"pid"], p[@"bundle"], p[@"architecture"], [NSDate date]];

    // MobileSafari's own writable container Caches directory.
    NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (cacheDir.length) {
        NSString *containerPath = [cacheDir stringByAppendingPathComponent:@"ioscontrol_safari_loaded.txt"];
        NSError *err = nil;
        if ([marker writeToFile:containerPath atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
            ICHTLog(@"[CTOR] marker written to container Caches: %@", containerPath);
        } else {
            ICHTLog(@"[CTOR] marker write failed at %@: %@", containerPath, err.localizedDescription);
        }
    } else {
        ICHTLog(@"[CTOR] no container Caches directory found");
    }

}
