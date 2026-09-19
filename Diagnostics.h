#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void ICHTLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT NSString *ICHTErrno(void);
FOUNDATION_EXPORT void ICHTWriteInjectionMarker(void);
FOUNDATION_EXPORT NSDictionary *ICHTProcessInfo(void);
