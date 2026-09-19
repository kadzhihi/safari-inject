#import "Diagnostics.h"
#import <errno.h>
#import <stdarg.h>
#import <string.h>

void ICHTLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[IOSControlSafariBridge] %@", message);
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
