#import <Foundation/Foundation.h>
@interface ICHTHTTPServer : NSObject
+ (instancetype)sharedServer;
- (void)start;
@end
