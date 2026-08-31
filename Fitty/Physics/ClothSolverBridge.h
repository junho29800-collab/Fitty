#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC++ façade over fitty::ClothSolver.
///
/// Memory: the C++ solver owns all particle / index buffers for the lifetime of this
/// object. Pointers returned here are valid until the next initializeGarment* call
/// (buffers are preallocated at init and only refilled, never reallocated on step).
/// Callers must copy if they need data after `self` is released.
///
/// Threading: every method except the trivial getters must be called from a single
/// serial queue. The Swift side never steps this from the main UI thread.
///
/// Exceptions: C++ exceptions are caught at this boundary and turned into no-ops.
/// Do not expect NSException either.
@interface ClothSolverBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWidth:(int)width
                       height:(int)height
                      spacing:(float)spacing NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(width:height:spacing:));

/// Packed capsules: 7 floats per capsule (ax, ay, az, bx, by, bz, radius). `count`
/// is the number of capsules, not the number of floats.
- (void)updateCapsulesWithData:(const float *)data count:(int)count NS_SWIFT_NAME(updateCapsules(data:count:));

/// Width/height of the isolated garment photo. <= 0 keeps body-only sizing.
/// Call before initializeGarment so the next placement can widen/lengthen the sheet.
- (void)setPhotoAspect:(float)aspect NS_SWIFT_NAME(setPhotoAspect(_:));

/// Place the garment on a torso. Each pointer is xyz world meters. `preferToward`
/// is typically the AR camera world position so the patch sits on the visible side.
- (void)initializeGarmentWithLeftShoulder:(const float *)leftShoulder
                            rightShoulder:(const float *)rightShoulder
                                  leftHip:(const float *)leftHip
                                 rightHip:(const float *)rightHip
                             preferToward:(const float *)preferToward NS_SWIFT_NAME(initializeGarment(leftShoulder:rightShoulder:leftHip:rightHip:preferToward:));

- (void)updateShoulderAnchorsWithLeft:(const float *)leftShoulder
                                right:(const float *)rightShoulder
                         preferToward:(const float *)preferToward NS_SWIFT_NAME(updateShoulderAnchors(left:right:preferToward:));

- (void)stepWithDeltaTime:(float)dt NS_SWIFT_NAME(step(deltaTime:));

@property (nonatomic, readonly) const float *positions;
@property (nonatomic, readonly) const float *normals;
@property (nonatomic, readonly) int particleCount;
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) const uint32_t *indices;
@property (nonatomic, readonly) int indexCount;

@end

NS_ASSUME_NONNULL_END
