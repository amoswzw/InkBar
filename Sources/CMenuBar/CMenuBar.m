#import "CMenuBar.h"
#import <dlfcn.h>
#import <objc/message.h>

static BOOL LoadFramework(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        loaded = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != NULL
            && NSClassFromString(@"MBAssessmentModeAssertion") != nil
            && NSClassFromString(@"MBAssessmentModeConfiguration") != nil;
    });
    return loaded;
}

@implementation IBVisibilityRestriction {
    id _assertion;
}

+ (BOOL)isAvailable {
    return LoadFramework();
}

- (BOOL)isActive {
    return _assertion != nil;
}

- (void)allowSystemItems:(NSArray<NSNumber *> *)systemItems
       bundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
              completion:(void (^)(NSError *_Nullable))completion {
    if (!LoadFramework()) {
        completion([NSError errorWithDomain:@"InkBar" code:1 userInfo:@{NSLocalizedDescriptionKey: @"MenuBarClientCore is not available on this macOS."}]);
        return;
    }
    id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(
        [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
        NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"), systemItems, bundleIdentifiers);
    // Activating an active assertion again can widen its list but not narrow it, so each change
    // takes a fresh assertion and drops the old one once the new one holds, leaving no gap.
    id previous = _assertion;
    id next = [NSClassFromString(@"MBAssessmentModeAssertion") new];
    _assertion = next;
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        next, NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), configuration,
        ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (previous) ((void (*)(id, SEL))objc_msgSend)(previous, NSSelectorFromString(@"invalidate"));
                completion(error);
            });
        });
}

- (void)invalidate {
    if (_assertion == nil) return;
    ((void (*)(id, SEL))objc_msgSend)(_assertion, NSSelectorFromString(@"invalidate"));
    _assertion = nil;
}

- (void)dealloc {
    [self invalidate];
}

@end
