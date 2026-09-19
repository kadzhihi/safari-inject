#import <Foundation/Foundation.h>

@interface ICHTSafariPage : NSObject
@property(nonatomic, strong) id webView;
@property(nonatomic, copy) NSString *url;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSDictionary *diagnostics;
@end
FOUNDATION_EXPORT ICHTSafariPage *ICHTFindActiveSafariPage(NSError **error);
