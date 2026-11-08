// The macOS 27 visibility mechanism was identified in Hidden Bar (MIT).
// See THIRD_PARTY_NOTICES.md. Runtime resolution is intentional: an OS change
// must leave every icon visible, rather than prevent the app from launching.
#import "NativeBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSError *BTError(NSString *message) {
    NSString *localized = NSLocalizedStringWithDefaultValue(message, @"Localizable", NSBundle.mainBundle, message, nil);
    return [NSError errorWithDomain:@"BarTidy.Visibility" code:1
                           userInfo:@{NSLocalizedDescriptionKey: localized}];
}

static void BTInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:@selector(invalidate)]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, @selector(invalidate));
        }
    } @catch (NSException *exception) {
        NSLog(@"BarTidy: visibility restore: %@", exception.reason);
    }
}

@implementation BTVisibilityController {
    id _assertion;
    NSUInteger _generation;
}

- (BOOL)available {
    static void *framework;
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                           RTLD_NOW | RTLD_LOCAL);
    }
    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return framework && configuration && assertion &&
        [configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] &&
        [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] &&
        [assertion instancesRespondToSelector:@selector(invalidate)];
}

- (BOOL)active { return _assertion != nil; }

- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles
                completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Visibility changes require the main thread");
    NSUInteger generation = ++_generation;
    if (!self.available) {
        [self restore];
        completion(BTError(@"Menu bar visibility is unavailable on this system. All icons remain visible."));
        return;
    }
    @try {
        NSMutableArray<NSNumber *> *systemItems = [NSMutableArray array];
        for (NSInteger index = 0; index < 64; index++) [systemItems addObject:@(index)];
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:), systemItems, bundles);
        id candidate = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !candidate) {
            [self restore];
            completion(BTError(@"Couldn't create the menu bar configuration. All icons remain visible."));
            return;
        }
        __block BOOL finished = NO;
        void (^finish)(NSError *) = ^(NSError *error) {
            if (finished) {
                if (self->_assertion != candidate) BTInvalidate(candidate);
                return;
            }
            finished = YES;
            if (generation != self->_generation) {
                BTInvalidate(candidate);
                completion(BTError(@"The menu bar request was cancelled."));
            } else if (error) {
                BTInvalidate(candidate);
                [self restore];
                completion(error);
            } else {
                id previous = self->_assertion;
                self->_assertion = candidate;
                BTInvalidate(previous);
                completion(nil);
            }
        };
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            candidate, @selector(activateWithConfiguration:completionHandler:), configuration,
            ^(NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{ finish(error); }); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!finished) finish(BTError(@"The system didn't respond in time. All icons have been restored."));
        });
    } @catch (NSException *exception) {
        [self restore];
        completion(BTError(exception.reason ?: @"The menu bar request failed."));
    }
}

- (void)restore {
    ++_generation;
    BTInvalidate(_assertion);
    _assertion = nil;
}

- (void)cancelPendingActivations {
    NSAssert(NSThread.isMainThread, @"Visibility changes require the main thread");
    ++_generation;
}

- (void)dealloc { BTInvalidate(_assertion); }
@end
