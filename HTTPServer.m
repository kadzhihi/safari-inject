#import "HTTPServer.h"
#import "Diagnostics.h"
#import "JavaScriptEvaluator.h"
#import "SafariPageFinder.h"
#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <stdlib.h>
#import <string.h>
#import <stdint.h>
#import <unistd.h>

static const NSUInteger ICHTMaxHeaderBytes = 16 * 1024;
static const NSUInteger ICHTMaxBodyBytes = 1024 * 1024;
static const NSTimeInterval ICHTJavaScriptTimeout = 10;

@implementation ICHTHTTPServer {
    int _listenFD;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedServer {
    static ICHTHTTPServer *server;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ server = [self new]; });
    return server;
}

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        self->_queue = dispatch_queue_create("com.ioscontrol.safarihttp", DISPATCH_QUEUE_SERIAL);
        dispatch_async(self->_queue, ^{ [self run]; });
    });
}

- (NSData *)jsonData:(NSDictionary *)object {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data) {
        ICHTLog(@"[HTTP] JSON serialization failed %@", error);
        return [@"{\"ok\":false,\"error\":\"JSON_SERIALIZATION_FAILED\"}" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return data;
}

- (BOOL)sendAll:(const void *)bytes length:(size_t)length fd:(int)fd {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = send(fd, cursor, length, 0);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            ICHTLog(@"[HTTP] send failed %@", ICHTErrno());
            return NO;
        }
        cursor += written;
        length -= (size_t)written;
    }
    return YES;
}

- (void)respond:(NSDictionary *)object status:(NSInteger)status fd:(int)fd {
    NSData *payload = [self jsonData:object];
    NSString *reason = status == 200 ? @"OK" : status == 400 ? @"Bad Request" : status == 404 ? @"Not Found" : status == 413 ? @"Payload Too Large" : @"Request Timeout";
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (long)status, reason, (unsigned long)payload.length];
    if ([self sendAll:header.UTF8String length:strlen(header.UTF8String) fd:fd]) [self sendAll:payload.bytes length:payload.length fd:fd];
}

- (NSDictionary *)status {
    __block NSError *error = nil;
    __block ICHTSafariPage *page = nil;
    if (!ICHTRunOnMainQueue(ICHTJavaScriptTimeout, ^{ page = ICHTFindActiveSafariPage(&error); })) {
        return @{ @"ok": @NO, @"stage": @"find-page", @"error": @"Timed out waiting for the main thread" };
    }
    if (!page) return @{ @"ok": @NO, @"stage": @"find-page", @"error": error.localizedDescription ?: @"No active Safari page" };
    NSMutableDictionary *output = [@{ @"ok": @YES, @"injected": @YES, @"webViewFound": @YES, @"url": page.url ?: @"", @"title": page.title ?: @"" } mutableCopy];
    [output addEntriesFromDictionary:ICHTProcessInfo()];
    [output addEntriesFromDictionary:page.diagnostics ?: @{}];
    return output;
}

- (NSDictionary *)scan {
    NSString *source = @"JSON.stringify(Array.from(document.querySelectorAll('input,textarea,select,[contenteditable=true]')).map(e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return {tag:e.tagName.toLowerCase(),type:e.type||'',id:e.id||'',name:e.name||'',placeholder:e.placeholder||'',value:e.value||e.textContent||'',visible:!!(r.width&&r.height&&s.visibility!=='hidden'&&s.display!=='none')}}))";
    NSDictionary *result = ICHTEvaluateJavaScript(source, ICHTJavaScriptTimeout);
    if (![result[@"ok"] boolValue]) return result;
    id encoded = result[@"result"];
    NSData *data = [encoded isKindOfClass:NSString.class] ? [encoded dataUsingEncoding:NSUTF8StringEncoding] : nil;
    id fields = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [fields isKindOfClass:NSArray.class] ? @{ @"ok": @YES, @"fields": fields } : @{ @"ok": @NO, @"stage": @"scan", @"error": @"Safari returned non-JSON scan data" };
}

- (NSDictionary *)fill:(NSData *)body {
    NSError *error = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
    if (![decoded isKindOfClass:NSDictionary.class]) return @{ @"ok": @NO, @"error": @"Expected a JSON object with selector and value" };
    NSDictionary *request = decoded;
    NSString *selector = [request[@"selector"] isKindOfClass:NSString.class] ? request[@"selector"] : nil;
    NSString *value = [request[@"value"] isKindOfClass:NSString.class] ? request[@"value"] : nil;
    if (!selector || !value) return @{ @"ok": @NO, @"error": @"Expected JSON selector and value strings" };

    NSData *selectorData = [NSJSONSerialization dataWithJSONObject:@[selector] options:0 error:nil];
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:nil];
    NSString *selectorLiteral = [[NSString alloc] initWithData:selectorData encoding:NSUTF8StringEncoding];
    NSString *valueLiteral = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    if (!selectorLiteral || !valueLiteral) return @{ @"ok": @NO, @"error": @"Failed to encode fill request" };

    NSString *source = [NSString stringWithFormat:@"(()=>{const s=%@[0],v=%@[0];let e;try{e=document.querySelector(s)}catch(_){return JSON.stringify({ok:false,error:'INVALID_SELECTOR'})}if(!e)return JSON.stringify({ok:false,error:'ELEMENT_NOT_FOUND'});if(e instanceof HTMLInputElement||e instanceof HTMLTextAreaElement){const p=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,d=Object.getOwnPropertyDescriptor(p,'value');if(d&&d.set)d.set.call(e,v);else e.value=v}else if(e instanceof HTMLSelectElement)e.value=v;else if(e.isContentEditable)e.textContent=v;else return JSON.stringify({ok:false,error:'UNSUPPORTED_ELEMENT'});e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return JSON.stringify({ok:true,selector:s,value:v})})()", selectorLiteral, valueLiteral];
    NSDictionary *result = ICHTEvaluateJavaScript(source, ICHTJavaScriptTimeout);
    if (![result[@"ok"] boolValue]) return result;
    NSData *data = [result[@"result"] isKindOfClass:NSString.class] ? [result[@"result"] dataUsingEncoding:NSUTF8StringEncoding] : nil;
    id payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [payload isKindOfClass:NSDictionary.class] ? payload : @{ @"ok": @NO, @"stage": @"fill", @"error": @"Safari returned invalid fill data" };
}

- (NSDictionary *)routeMethod:(NSString *)method path:(NSString *)path body:(NSData *)body status:(NSInteger *)status {
    *status = 200;
    if ([method isEqual:@"GET"] && [path isEqual:@"/ping"]) {
        NSMutableDictionary *output = [@{ @"ok": @YES, @"bridge": @"IOSControlSafariBridge", @"version": @"0.2.0", @"port": @17891 } mutableCopy];
        [output addEntriesFromDictionary:ICHTProcessInfo()];
        return output;
    }
    if ([method isEqual:@"GET"] && [path isEqual:@"/status"]) return [self status];
    if ([method isEqual:@"GET"] && [path isEqual:@"/scan"]) return [self scan];
    if ([method isEqual:@"POST"] && [path isEqual:@"/eval"]) {
        NSString *source = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        return source.length ? ICHTEvaluateJavaScript(source, ICHTJavaScriptTimeout) : @{ @"ok": @NO, @"error": @"EMPTY_BODY" };
    }
    if ([method isEqual:@"POST"] && [path isEqual:@"/fill"]) return [self fill:body];
    *status = 404;
    return @{ @"ok": @NO, @"error": @"NOT_FOUND" };
}

- (BOOL)readRequestFrom:(int)fd method:(NSString **)method path:(NSString **)path body:(NSData **)body error:(NSDictionary **)errorResponse status:(NSInteger *)status {
    NSMutableData *request = [NSMutableData data];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    char buffer[4096];
    NSRange headerRange = { NSNotFound, 0 };
    while (headerRange.location == NSNotFound) {
        ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
        if (count <= 0) { *status = 408; *errorResponse = @{ @"ok": @NO, @"error": @"REQUEST_TIMEOUT_OR_DISCONNECT", @"detail": ICHTErrno() }; return NO; }
        [request appendBytes:buffer length:(NSUInteger)count];
        headerRange = [request rangeOfData:separator options:0 range:NSMakeRange(0, request.length)];
        if (headerRange.location == NSNotFound && request.length > ICHTMaxHeaderBytes) { *status = 413; *errorResponse = @{ @"ok": @NO, @"error": @"HEADER_TOO_LARGE" }; return NO; }
    }
    if (headerRange.location > ICHTMaxHeaderBytes) { *status = 413; *errorResponse = @{ @"ok": @NO, @"error": @"HEADER_TOO_LARGE" }; return NO; }
    NSString *headerText = [[NSString alloc] initWithData:[request subdataWithRange:NSMakeRange(0, headerRange.location)] encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *requestLine = [lines.firstObject componentsSeparatedByString:@" "];
    if (!headerText || requestLine.count != 3 || ![requestLine[2] hasPrefix:@"HTTP/"]) { *status = 400; *errorResponse = @{ @"ok": @NO, @"error": @"MALFORMED_REQUEST" }; return NO; }
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSRange colon = [lines[index] rangeOfString:@":"];
        if (colon.location == NSNotFound) { *status = 400; *errorResponse = @{ @"ok": @NO, @"error": @"MALFORMED_HEADER" }; return NO; }
        NSString *key = [[lines[index] substringToIndex:colon.location] lowercaseString];
        NSString *value = [[lines[index] substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!key.length || headers[key]) { *status = 400; *errorResponse = @{ @"ok": @NO, @"error": @"DUPLICATE_OR_EMPTY_HEADER" }; return NO; }
        headers[key] = value;
    }
    NSUInteger contentLength = 0;
    NSString *contentLengthValue = headers[@"content-length"];
    if ([requestLine[0] isEqual:@"POST"] && !contentLengthValue) { *status = 400; *errorResponse = @{ @"ok": @NO, @"error": @"MISSING_CONTENT_LENGTH" }; return NO; }
    if (contentLengthValue) {
        if (contentLengthValue.length == 0) { *status = 413; *errorResponse = @{ @"ok": @NO, @"error": @"INVALID_OR_TOO_LARGE_CONTENT_LENGTH" }; return NO; }
        NSCharacterSet *nonDigits = [NSCharacterSet decimalDigitCharacterSet].invertedSet;
        if ([contentLengthValue rangeOfCharacterFromSet:nonDigits].location != NSNotFound) { *status = 413; *errorResponse = @{ @"ok": @NO, @"error": @"INVALID_OR_TOO_LARGE_CONTENT_LENGTH" }; return NO; }
        const char *rawContentLength = [contentLengthValue UTF8String];
        char *end = NULL;
        errno = 0;
        unsigned long long parsedContentLength = rawContentLength ? strtoull(rawContentLength, &end, 10) : 0;
        if (!rawContentLength || errno == ERANGE || end == rawContentLength || *end != '\0' || parsedContentLength > (unsigned long long)ICHTMaxBodyBytes) { *status = 413; *errorResponse = @{ @"ok": @NO, @"error": @"INVALID_OR_TOO_LARGE_CONTENT_LENGTH" }; return NO; }
        contentLength = (NSUInteger)parsedContentLength;
    }
    NSUInteger bodyOffset = headerRange.location + separator.length;
    while (request.length - bodyOffset < contentLength) {
        ssize_t count = recv(fd, buffer, MIN(sizeof(buffer), contentLength - (request.length - bodyOffset)), 0);
        if (count <= 0) { *status = 408; *errorResponse = @{ @"ok": @NO, @"error": @"BODY_TIMEOUT_OR_DISCONNECT", @"detail": ICHTErrno() }; return NO; }
        [request appendBytes:buffer length:(NSUInteger)count];
    }
    *method = requestLine[0];
    *path = [[requestLine[1] componentsSeparatedByString:@"?"] firstObject] ?: @"/";
    *body = [request subdataWithRange:NSMakeRange(bodyOffset, contentLength)];
    return YES;
}

- (void)serve:(int)fd {
    struct timeval timeout = { .tv_sec = 15, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    NSString *method = nil, *path = nil; NSData *body = nil; NSDictionary *errorResponse = nil; NSInteger status = 400;
    if ([self readRequestFrom:fd method:&method path:&path body:&body error:&errorResponse status:&status]) {
        NSDictionary *response = [self routeMethod:method path:path body:body status:&status];
        [self respond:response status:status fd:fd];
    } else {
        ICHTLog(@"[HTTP] malformed request: %@", errorResponse);
        [self respond:errorResponse ?: @{ @"ok": @NO, @"error": @"MALFORMED_REQUEST" } status:status fd:fd];
    }
    close(fd);
}

- (void)run {
    ICHTLog(@"[HTTP] start");

    _listenFD = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenFD < 0) {
        NSString *detail = ICHTErrno();
        ICHTLog(@"[HTTP] socket FAILED %@", detail);
        return;
    }
    ICHTLog(@"[HTTP] socket OK");

    int one = 1;
    if (setsockopt(_listenFD, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) != 0) {
        ICHTLog(@"[HTTP] SO_REUSEADDR failed %@", ICHTErrno());
    }
#ifdef SO_NOSIGPIPE
    if (setsockopt(_listenFD, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) {
        ICHTLog(@"[HTTP] SO_NOSIGPIPE failed %@", ICHTErrno());
    }
#endif

    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(17891);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    BOOL bound = NO;
    NSString *lastBindError = nil;
    for (NSInteger attempt = 1; attempt <= 3; attempt++) {
        if (bind(_listenFD, (struct sockaddr *)&address, sizeof(address)) == 0) {
            bound = YES;
            break;
        }
        lastBindError = ICHTErrno();
        ICHTLog(@"[HTTP] bind attempt %ld FAILED %@", (long)attempt, lastBindError);
        if (attempt < 3) usleep(250000);
    }

    if (!bound) {
        close(_listenFD);
        _listenFD = -1;
        return;
    }
    ICHTLog(@"[HTTP] bind OK 127.0.0.1:17891");

    if (listen(_listenFD, 8) != 0) {
        NSString *detail = ICHTErrno();
        ICHTLog(@"[HTTP] listen FAILED %@", detail);
        close(_listenFD);
        _listenFD = -1;
        return;
    }

    ICHTLog(@"[HTTP] LISTENING 127.0.0.1:17891");
    ICHTLog(@"[HTTP] accept loop started");

    for (;;) {
        int client = accept(_listenFD, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            ICHTLog(@"[HTTP] accept failed %@", ICHTErrno());
            continue;
        }
        [self serve:client];
    }
}
@end
