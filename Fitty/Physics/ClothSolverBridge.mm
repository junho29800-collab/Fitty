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
    if (_solver == nullptr || data == nullptr || count <= 0) return;
    try {
        _solver->setCapsules(data, count);
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
