#import <Foundation/Foundation.h>

typedef void (*ICHTRuntimeStatusCallback)(const char *message);

FOUNDATION_EXPORT __attribute__((visibility("default"))) BOOL
ICHTPayloadStart(ICHTRuntimeStatusCallback callback);

FOUNDATION_EXPORT void ICHTReportRuntimeStatus(NSString *message);
