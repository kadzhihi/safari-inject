#import "SafariPageFinder.h"
#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSUInteger ICHTMaxSelectorWalkObjects = 128;

@implementation ICHTSafariPage
@end

static void ICHTAddVisibleViewTree(UIView *view, NSMutableArray *objects, NSUInteger depth) {
    if (!view || view.hidden || view.alpha <= 0 || depth > 40) return;
    [objects addObject:view];
    for (UIView *child in view.subviews) ICHTAddVisibleViewTree(child, objects, depth + 1);
}

static void ICHTAddControllerChain(UIViewController *controller, NSMutableArray *objects) {
    if (!controller || [objects containsObject:controller]) return;
    [objects addObject:controller];
    ICHTAddControllerChain(controller.presentedViewController, objects);
    if ([controller isKindOfClass:UINavigationController.class]) ICHTAddControllerChain(((UINavigationController *)controller).topViewController, objects);
    if ([controller isKindOfClass:UITabBarController.class]) ICHTAddControllerChain(((UITabBarController *)controller).selectedViewController, objects);
}

static id ICHTObjectValue(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    Method method = class_getInstanceMethod([object class], selector);
    if (!method) return nil;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@') return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (NSException *exception) {
        ICHTLog(@"[PAGE] %@ on %@ raised %@", selectorName, NSStringFromClass([object class]), exception.reason);
        return nil;
    }
}

static BOOL ICHTCanEvaluateJavaScript(id object) {
    return object && [object respondsToSelector:NSSelectorFromString(@"evaluateJavaScript:completionHandler:")];
}

static NSString *ICHTStringValue(id object, NSString *selectorName) {
    id value = ICHTObjectValue(object, selectorName);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return ((NSURL *)value).absoluteString;
    return @"";
}

static ICHTSafariPage *ICHTPageFromEvaluator(id evaluator, NSString *strategy) {
    ICHTSafariPage *page = [ICHTSafariPage new];
    page.webView = evaluator;
    page.url = ICHTStringValue(evaluator, @"URL");
    page.title = ICHTStringValue(evaluator, @"title");
    page.diagnostics = @{ @"class": NSStringFromClass([evaluator class]), @"strategy": strategy };
    ICHTLog(@"[PAGE] found %@", page.diagnostics);
    return page;
}

ICHTSafariPage *ICHTFindActiveSafariPage(NSError **error) {
    if (!NSThread.isMainThread) {
        if (error) *error = [NSError errorWithDomain:@"IOSControlSafariHTTP" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Safari page discovery must run on the main thread" }];
        return nil;
    }
    ICHTLog(@"[PAGE] searching");
    NSMutableArray *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
    }
    if (!windows.count) [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
    NSArray *orderedWindows = [windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *left, UIWindow *right) {
        if (left.isKeyWindow != right.isKeyWindow) return left.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray *objects = [NSMutableArray array];
    for (UIWindow *window in orderedWindows) {
        if (window.hidden || window.alpha <= 0) continue;
        ICHTAddVisibleViewTree(window, objects, 0);
        ICHTAddControllerChain(window.rootViewController, objects);
    }
    Class wkWebView = NSClassFromString(@"WKWebView");
    for (id object in objects) {
        if ((wkWebView && [object isKindOfClass:wkWebView]) || ICHTCanEvaluateJavaScript(object)) return ICHTPageFromEvaluator(object, @"visible-view-tree");
    }

    // Safari may wrap the evaluating view. Traverse only object-returning, selector-checked links from visible UI objects.
    NSArray<NSString *> *links = @[ @"webView", @"_webView", @"contentView", @"activeTab", @"currentTab", @"document", @"browserController" ];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *queue = [objects mutableCopy];
    for (NSUInteger index = 0; index < queue.count && index < ICHTMaxSelectorWalkObjects; index++) {
        id object = queue[index];
        if (!object || [seen containsObject:object]) continue;
        [seen addObject:object];
        if (ICHTCanEvaluateJavaScript(object)) return ICHTPageFromEvaluator(object, @"bounded-selector-walk");
        for (NSString *link in links) {
            id child = ICHTObjectValue(object, link);
            if (child && child != object && ![seen containsObject:child]) [queue addObject:child];
        }
    }
    NSString *detail = [NSString stringWithFormat:@"inspected %lu visible UI objects across %lu candidate windows", (unsigned long)objects.count, (unsigned long)orderedWindows.count];
    ICHTLog(@"[PAGE] not found: %@", detail);
    if (error) *error = [NSError errorWithDomain:@"IOSControlSafariHTTP" code:1 userInfo:@{ NSLocalizedDescriptionKey: detail }];
    return nil;
}
