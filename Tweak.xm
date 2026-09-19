#import <Foundation/Foundation.h>
#import "Diagnostics.h"
#import "HTTPServer.h"

%ctor {
    @autoreleasepool {
        ICHTLog(@"[CTOR] loaded %@", ICHTProcessInfo());
        ICHTWriteInjectionMarker();
        [[ICHTHTTPServer sharedServer] start];
    }
}
