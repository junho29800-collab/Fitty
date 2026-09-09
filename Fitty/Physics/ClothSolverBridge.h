#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC++ façade over fitty::ClothSolver.
///
/// Memory: the C++ solver owns all particle / index buffers for the lifetime of this
/// object. Pointers returned here are valid until the next initializeGarment* or
/// setQuality* call. Callers must copy if they need data after `self` is released.
///
/// Threading: every method except the trivial getters must be called from a single
/// serial queue (`com.junholee.Fitty.pbd`). The Swift side never steps this from
/// the main UI thread.
///
/// Exceptions: C++ exceptions are caught at this boundary and turned into no-ops.
@interface ClothSolverBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWidth:(int)width
                       height:(int)height
                      spacing:(float)spacing NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(width:height:spacing:));

/// Packed capsules: 7 floats per capsule (ax, ay, az, bx, by, bz, radius). `count`
/// is the number of capsules, not the number of floats.
- (void)updateCapsulesWithData:(const float *)data count:(int)count NS_SWIFT_NAME(updateCapsules(data:count:));

/// Width/height of the isolated garment photo. <= 0 keeps body-only sizing.
- (void)setPhotoAspect:(float)aspect NS_SWIFT_NAME(setPhotoAspect(_:));

/// Fabric / solver config. Mass kg, damping [0,1], stretch/shear/bend [0,1], friction [0,1].
- (void)setConfigWithMass:(float)mass
                  damping:(float)damping
                  stretch:(float)stretch
                    shear:(float)shear
                     bend:(float)bend
                 friction:(float)friction NS_SWIFT_NAME(setConfig(mass:damping:stretch:shear:bend:friction:));

/// World-space wind acceleration (m/s²) applied in Verlet.
- (void)setWindX:(float)x y:(float)y z:(float)z NS_SWIFT_NAME(setWind(x:y:z:));

/// XPBD stretch compliance α (m/N). 0 = hard constraint. See ClothSolver.hpp.
- (void)setXPBDCompliance:(float)alpha NS_SWIFT_NAME(setXPBDCompliance(_:));

- (void)enableSelfCollision:(BOOL)on NS_SWIFT_NAME(enableSelfCollision(_:));

/// Packed volume ellipsoids: 12 floats each (cx,cy,cz, rx,ry,rz, ux,uy,uz, vx,vy,vz).
- (void)setVolumeEllipsoidsWithData:(const float *)data count:(int)count NS_SWIFT_NAME(setVolumeEllipsoids(data:count:));

/// Upper-arm capsules for the sleeve approximation (7 floats each).
- (void)setArmCapsulesWithData:(const float *)data count:(int)count NS_SWIFT_NAME(setArmCapsules(data:count:));

/// Rebuild the particle grid (Low 16×20 / Med 24×32 / High 32×40).
- (void)setQualityWidth:(int)width height:(int)height spacing:(float)spacing NS_SWIFT_NAME(setQuality(width:height:spacing:));

/// Pin mode: 0 tee, 1 tank, 2 hoodie, 3 dress, 4 pants. Matches fitty::PinMode.
- (void)setPinMode:(int)mode NS_SWIFT_NAME(setPinMode(_:));

- (void)setSizeScale:(float)scale NS_SWIFT_NAME(setSizeScale(_:));
- (void)setFitLength:(float)length tightness:(float)tightness drape:(float)drape NS_SWIFT_NAME(setFit(length:tightness:drape:));
- (void)setBodyScale:(float)scale NS_SWIFT_NAME(setBodyScale(_:));

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
