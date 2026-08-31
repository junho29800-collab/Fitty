#import "ClothSolverBridge.h"

#include "ClothSolver.hpp"

#include <memory>

namespace {
fitty::Vec3 load3(const float *p) {
    return fitty::Vec3{p[0], p[1], p[2]};
}
} // namespace

@implementation ClothSolverBridge {
    std::unique_ptr<fitty::ClothSolver> _solver;
}

- (instancetype)initWithWidth:(int)width height:(int)height spacing:(float)spacing {
    self = [super init];
    if (self) {
        try {
            _solver = std::make_unique<fitty::ClothSolver>(width, height, spacing);
        } catch (...) {
            _solver.reset();
        }
    }
    return self;
}

- (void)updateCapsulesWithData:(const float *)data count:(int)count {
    if (_solver == nullptr) return;
    try {
        _solver->setCapsules(data, count);
    } catch (...) {
    }
}

- (void)setPhotoAspect:(float)aspect {
    if (_solver == nullptr) return;
    try {
        _solver->setPhotoAspect(aspect);
    } catch (...) {
    }
}

- (void)setConfigWithMass:(float)mass
                  damping:(float)damping
                  stretch:(float)stretch
                    shear:(float)shear
                     bend:(float)bend
                 friction:(float)friction {
    if (_solver == nullptr) return;
    try {
        fitty::ClothConfig c = _solver->config();
        c.particleMass = mass;
        c.damping = damping;
        c.structuralStiffness = stretch;
        c.shearStiffness = shear;
        c.bendStiffness = bend;
        c.collisionFriction = friction;
        _solver->setConfig(c);
    } catch (...) {
    }
}

- (void)setWindX:(float)x y:(float)y z:(float)z {
    if (_solver == nullptr) return;
    try {
        _solver->setWind(fitty::Vec3{x, y, z});
    } catch (...) {
    }
}

- (void)setXPBDCompliance:(float)alpha {
    if (_solver == nullptr) return;
    try {
        _solver->setXPBDCompliance(alpha);
    } catch (...) {
    }
}

- (void)enableSelfCollision:(BOOL)on {
    if (_solver == nullptr) return;
    try {
        _solver->enableSelfCollision(on ? true : false);
    } catch (...) {
    }
}

- (void)setVolumeEllipsoidsWithData:(const float *)data count:(int)count {
    if (_solver == nullptr) return;
    try {
        _solver->setVolumeEllipsoids(data, count);
    } catch (...) {
    }
}

- (void)setArmCapsulesWithData:(const float *)data count:(int)count {
    if (_solver == nullptr) return;
    try {
        _solver->setArmCapsules(data, count);
    } catch (...) {
    }
}

- (void)setQualityWidth:(int)width height:(int)height spacing:(float)spacing {
    if (_solver == nullptr) return;
    try {
        _solver->setQuality(width, height, spacing);
    } catch (...) {
    }
}

- (void)setPinMode:(int)mode {
    if (_solver == nullptr) return;
    try {
        _solver->setPinMode(static_cast<fitty::PinMode>(mode));
    } catch (...) {
    }
}

- (void)setSizeScale:(float)scale {
    if (_solver == nullptr) return;
    try {
        _solver->setSizeScale(scale);
    } catch (...) {
    }
}

- (void)setFitLength:(float)length tightness:(float)tightness drape:(float)drape {
    if (_solver == nullptr) return;
    try {
        _solver->setFit(length, tightness, drape);
    } catch (...) {
    }
}

- (void)setBodyScale:(float)scale {
    if (_solver == nullptr) return;
    try {
        _solver->setBodyScale(scale);
    } catch (...) {
    }
}

- (void)initializeGarmentWithLeftShoulder:(const float *)leftShoulder
                            rightShoulder:(const float *)rightShoulder
                                  leftHip:(const float *)leftHip
                                 rightHip:(const float *)rightHip
                             preferToward:(const float *)preferToward {
    if (_solver == nullptr || leftShoulder == nullptr || rightShoulder == nullptr ||
        leftHip == nullptr || rightHip == nullptr || preferToward == nullptr) {
        return;
    }
    try {
        _solver->initializeGarment(load3(leftShoulder),
                                   load3(rightShoulder),
                                   load3(leftHip),
                                   load3(rightHip),
                                   load3(preferToward));
    } catch (...) {
    }
}

- (void)updateShoulderAnchorsWithLeft:(const float *)leftShoulder
                                right:(const float *)rightShoulder
                         preferToward:(const float *)preferToward {
    if (_solver == nullptr || leftShoulder == nullptr || rightShoulder == nullptr ||
        preferToward == nullptr) {
        return;
    }
    try {
        _solver->updateShoulderAnchors(load3(leftShoulder), load3(rightShoulder), load3(preferToward));
    } catch (...) {
    }
}

- (void)stepWithDeltaTime:(float)dt {
    if (_solver == nullptr) return;
    try {
        _solver->step(dt);
    } catch (...) {
    }
}

- (const float *)positions {
    return _solver ? _solver->positions() : nullptr;
}

- (const float *)normals {
    return _solver ? _solver->normals() : nullptr;
}

- (int)particleCount {
    return _solver ? _solver->particleCount() : 0;
}

- (int)width {
    return _solver ? _solver->width() : 0;
}

- (int)height {
    return _solver ? _solver->height() : 0;
}

- (const uint32_t *)indices {
    return _solver ? _solver->indices() : nullptr;
}

- (int)indexCount {
    return _solver ? _solver->indexCount() : 0;
}

@end
