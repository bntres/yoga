/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/runtime.h>
#import "UIView+Yoga.h"
#import "YGLayout+Private.h"

static const void* kYGYogaAssociatedKey = &kYGYogaAssociatedKey;

@implementation UIView (YogaKit)

- (YGLayout*)yoga {
    YGLayout* yoga = objc_getAssociatedObject(self, kYGYogaAssociatedKey);
    if (!yoga) {
        yoga = [[YGLayout alloc] initWithView:self];
        objc_setAssociatedObject(self, kYGYogaAssociatedKey, yoga, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return yoga;
}

- (BOOL)isYogaEnabled {
    return objc_getAssociatedObject(self, kYGYogaAssociatedKey) != nil;
}

- (void)configureLayoutWithBlock:(NS_NOESCAPE YGLayoutConfigurationBlock)block {
    if (block) {
        [self.yoga configureLayoutWithBlock:block];
    }
}

@end

NS_INLINE BOOL CGRectIsStandlized(CGRect rect) {
    CGFloat x = CGRectGetMinX(rect), y = CGRectGetMinY(rect);
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);

    return !(isnan(x) || isinf(x) ||
             isnan(y) || isinf(y) ||
             isnan(w) || isinf(w) ||
             isnan(h) || isinf(h));
}

NS_INLINE CGRect StandlizedRect(CGRect rect) {
    if (CGRectIsStandlized(rect)) {
        return rect;
    }

    CGFloat x = CGRectGetMinX(rect), y = CGRectGetMinY(rect);
    CGPoint origin = rect.origin;

    origin.x = isnan(x) || isinf(x) ? 0 : x;
    origin.y = isnan(y) || isinf(y) ? 0 : y;

    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    CGSize size = rect.size;

    size.width = isnan(w) || isinf(w) ? 0 : w;
    size.height = isnan(h) || isinf(h) ? 0 : h;

    return (CGRect){ origin, size };
}

#if TARGET_OS_OSX
NS_INLINE NSSize StandlizedSize(NSSize size) {
    return StandlizedRect((CGRect){ CGPointZero, size }).size;
}
#endif

static void YogaSwizzleInstanceMethod(Class cls, SEL originalSelector, SEL swizzledSelector);

@implementation UIView (YogaKitAutoApplyLayout)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YogaSwizzleInstanceMethod(self, @selector(initWithFrame:), @selector(_yoga_initWithFrame:));
        YogaSwizzleInstanceMethod(self, @selector(setFrame:), @selector(_yoga_setFrame:));
        YogaSwizzleInstanceMethod(self, @selector(setBounds:), @selector(_yoga_setBounds:));
#if TARGET_OS_OSX
        YogaSwizzleInstanceMethod(self, @selector(setFrameSize:), @selector(_yoga_setFrameSize:));
        YogaSwizzleInstanceMethod(self, @selector(setBoundsSize:), @selector(_yoga_setBoundsSize:));
#endif
    });
}

- (instancetype)_yoga_initWithFrame:(CGRect)frame {
    id _self = [self _yoga_initWithFrame:StandlizedRect(frame)];
    if (_self) {
        [self _yoga_applyLayout];
    }

    return _self;
}

- (void)_yoga_setFrame:(CGRect)frame {
    [self _yoga_setFrame:StandlizedRect(frame)];

    [self _yoga_applyLayout];
}

- (void)_yoga_setBounds:(CGRect)bounds {
    [self _yoga_setBounds:StandlizedRect(bounds)];

    [self _yoga_applyLayout];
}

#if TARGET_OS_OSX
- (void)_yoga_setFrameSize:(NSSize)newSize {
    [self _yoga_setFrameSize:StandlizedSize(newSize)];

    [self _yoga_applyLayout];
}

- (void)_yoga_setBoundsSize:(NSSize)newSize {
    [self _yoga_setBoundsSize:StandlizedSize(newSize)];

    [self _yoga_applyLayout];
}
#endif

- (void)_yoga_applyLayout {
    if (self.isYogaEnabled) {
        YGLayout *yoga = self.yoga;
        if (yoga.isIncludedInLayout) {
            [yoga applyLayoutPreservingOrigin:YES];
        }
    }
}

@end


static void YogaSwizzleInstanceMethod(Class cls, SEL originalSelector, SEL swizzledSelector) {
    if (!cls || !originalSelector || !swizzledSelector) {
        return;
    }

    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    if (!originalMethod || !swizzledMethod) {
        return;
    }

    IMP swizzledIMP = method_getImplementation(swizzledMethod);
    if (class_addMethod(cls, originalSelector, swizzledIMP, method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(cls,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

