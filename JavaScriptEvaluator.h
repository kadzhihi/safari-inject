#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
FOUNDATION_EXPORT NSDictionary *ICHTEvaluateJavaScript(NSString *source, NSTimeInterval timeout);
FOUNDATION_EXPORT BOOL ICHTRunOnMainQueue(NSTimeInterval timeout, dispatch_block_t block);
