#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The menu bar allowlist that macOS 27 keeps for assessment (exam) mode, from the private
/// MenuBarClientCore framework. While it is active, only the listed system items and the
/// status items of the listed apps are drawn. The system drops it when this process exits.
@interface IBVisibilityRestriction : NSObject

+ (BOOL)isAvailable;

/// System items are MBSystemItemIdentifier raw values. Replaces any allowlist applied before.
- (void)allowSystemItems:(NSArray<NSNumber *> *)systemItems
       bundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
              completion:(void (^)(NSError *_Nullable error))completion;

- (void)invalidate;

@property (nonatomic, readonly, getter=isActive) BOOL active;

@end

NS_ASSUME_NONNULL_END
