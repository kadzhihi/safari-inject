#import "JavaScriptEvaluator.h"
#import "SafariPageFinder.h"
#import <objc/message.h>
#import <stdint.h>

static NSDictionary *ICHTJavaScriptError(NSString *message) {
    return @{ @"ok": @NO, @"stage": @"javascript", @"error": message ?: @"Unknown JavaScript error" };
}

BOOL ICHTRunOnMainQueue(NSTimeInterval timeout, dispatch_block_t block) {
    if (!block) return NO;
    if (NSThread.isMainThread) {
        block();
        return YES;
    }

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        block();
        dispatch_semaphore_signal(finished);
    });
    return dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0;
}

NSDictionary *ICHTEvaluateJavaScript(NSString *source, NSTimeInterval timeout) {
    if (![source isKindOfClass:NSString.class] || source.length == 0) return ICHTJavaScriptError(@"EMPTY_BODY");

    SEL selector = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    __block id result = nil;
    __block NSError *evaluationError = nil;
    __block NSError *pageError = nil;
    __block BOOL didStart = NO;
    if (!ICHTRunOnMainQueue(timeout, ^{
        ICHTSafariPage *page = ICHTFindActiveSafariPage(&pageError);
        id evaluator = page.webView;
        NSMethodSignature *signature = [evaluator methodSignatureForSelector:selector];
        if (!evaluator || ![evaluator respondsToSelector:selector] || !signature || signature.numberOfArguments != 4 || signature.methodReturnType[0] != 'v') {
            if (!pageError) pageError = [NSError errorWithDomain:@"IOSControlSafariHTTP" code:3 userInfo:@{ NSLocalizedDescriptionKey: @"Selected Safari object cannot evaluate JavaScript" }];
            return;
        }
        didStart = YES;
        ((void (*)(id, SEL, NSString *, void (^)(id, NSError *)))objc_msgSend)(evaluator, selector, source, ^(id value, NSError *error) {
            result = value;
            evaluationError = error;
            dispatch_semaphore_signal(completed);
        });
    })) return ICHTJavaScriptError(@"Timed out waiting for the main thread");
    if (!didStart) return ICHTJavaScriptError(pageError.localizedDescription ?: @"No active Safari page");
    if (dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        return ICHTJavaScriptError(@"JavaScript evaluation timed out");
    }
    if (evaluationError) return ICHTJavaScriptError(evaluationError.localizedDescription);

    id jsonResult = result ?: NSNull.null;
    if (![NSJSONSerialization isValidJSONObject:@{ @"result": jsonResult }]) jsonResult = [jsonResult description] ?: @"";
    return @{ @"ok": @YES, @"result": jsonResult };
}
