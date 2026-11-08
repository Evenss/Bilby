#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// All methods and callbacks run on the main thread. The assertion only changes
/// menu bar visibility; no assessment session or other restrictions are started.
@interface BTVisibilityController : NSObject
@property(nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) BOOL active;
- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles
                completion:(void (^)(NSError * _Nullable error))completion;
- (void)restore;
/// Cancel unfinished activations while retaining the last active assertion.
- (void)cancelPendingActivations;
@end

NS_ASSUME_NONNULL_END
