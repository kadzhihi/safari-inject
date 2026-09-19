#import "JavaScriptEvaluator.h"
#import "SafariPageFinder.h"
#import "Diagnostics.h"

@protocol ICHTJavaScriptEvaluating <NSObject>
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id result, NSError *error))completionHandler;
@end

static id ICHTJSONSafeValue(id value) {
    if (!value || value == [NSNull null]) return [NSNull null];
    if ([NSJSONSerialization isValidJSONObject:@[value]]) return value;
    return [value description] ?: @"";
}

BOOL ICHTRunOnMainQueue(NSTimeInterval timeout, dispatch_block_t block) {
    if (NSThread.isMainThread) { block(); return YES; }
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{ block(); dispatch_semaphore_signal(completed); });
    return dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0;
}

NSDictionary *ICHTEvaluateJavaScript(NSString *source, NSTimeInterval timeout) {
    if (![source isKindOfClass:NSString.class] || !source.length) return @{ @"ok": @NO, @"stage": @"javascript", @"error": @"Empty JavaScript source" };
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    __block ICHTSafariPage *page = nil;
    __block NSError *findError = nil;
    __block id result = nil;
    __block NSError *javaScriptError = nil;
    __block BOOL settled = NO; // Accessed only on the main queue.
    __block BOOL evaluationStarted = NO;
    ICHTLog(@"[JS] evaluating");
    if (!ICHTRunOnMainQueue(timeout, ^{
        page = ICHTFindActiveSafariPage(&findError);
        if (!page || settled) return;
        evaluationStarted = YES;
        id<ICHTJavaScriptEvaluating> evaluator = (id<ICHTJavaScriptEvaluating>)page.webView;
        [evaluator evaluateJavaScript:source completionHandler:^(id value, NSError *error) {
            if (settled) return;
            settled = YES;
            result = value;
            javaScriptError = error;
            dispatch_semaphore_signal(completed);
        }];
    })) {
        return @{ @"ok": @NO, @"stage": @"find-page", @"error": @"Timed out waiting for the main thread" };
    }
    if (!page) return @{ @"ok": @NO, @"stage": @"find-page", @"error": findError.localizedDescription ?: @"No active Safari page found" };
    if (!evaluationStarted) return @{ @"ok": @NO, @"stage": @"javascript", @"error": @"Could not begin JavaScript evaluation" };
    if (dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ settled = YES; });
        ICHTLog(@"[JS] timed out");
        return @{ @"ok": @NO, @"stage": @"javascript", @"error": @"Timed out waiting for Safari JavaScript completion" };
    }
    if (javaScriptError) {
        ICHTLog(@"[JS] failed %@", javaScriptError);
        return @{ @"ok": @NO, @"stage": @"javascript", @"error": javaScriptError.localizedDescription ?: @"JavaScript error", @"exception": javaScriptError.description ?: @"" };
    }
    ICHTLog(@"[JS] completed");
    return @{ @"ok": @YES, @"result": ICHTJSONSafeValue(result) };
}
