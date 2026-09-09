#include "ClothSolver.hpp"

#include <algorithm>
#include <cstring>

namespace fitty {
namespace {

constexpr float kMinDt = 1e-5f;
constexpr float kMaxSubstepDt = 1.f / 30.f;
constexpr float kEps = 1e-8f;
constexpr int kSelfCollisionSkipN = 1600;
constexpr int kHashBuckets = 512;

float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

Vec3 closestPointOnSegment(const Vec3& p, const Vec3& a, const Vec3& b) {
    const Vec3 ab = b - a;
    const float ab2 = length2(ab);
    if (ab2 < kEps) return a;
    const float t = clampf(dot(p - a, ab) / ab2, 0.f, 1.f);
    return a + ab * t;
}

float hash01(int i, float t) {
    // Cheap deterministic noise in [0,1). Not crypto; just wind flutter.
    const float s = sinf(static_cast<float>(i) * 12.9898f + t * 3.71f) * 43758.5453f;
    return s - floorf(s);
}

int wrapBucket(int h) {
    const int m = h % kHashBuckets;
    return m < 0 ? m + kHashBuckets : m;
}

} // namespace

ClothSolver::ClothSolver(int width, int height, float spacing) {
    rebuildBuffers(width, height, spacing);
    initializeGarment(Vec3{-0.18f, 1.45f, -2.0f},
                      Vec3{ 0.18f, 1.45f, -2.0f},
                      Vec3{-0.12f, 0.95f, -2.0f},
                      Vec3{ 0.12f, 0.95f, -2.0f},
                      Vec3{ 0.f, 1.5f, 0.f});
}

void ClothSolver::rebuildBuffers(int width, int height, float spacing) {
    width_ = std::max(2, width);
    height_ = std::max(2, height);
    spacing_ = spacing > 1e-4f ? spacing : 0.02f;
    const int n = width_ * height_;
    particles_.assign(static_cast<size_t>(n), Particle{});
    for (int row = 0; row < height_; ++row) {
        for (int col = 0; col < width_; ++col) {
            Particle& p = particles_[static_cast<size_t>(indexOf(col, row))];
            p.col = col;
            p.row = row;
        }
    }
    positions_.assign(static_cast<size_t>(n * 3), 0.f);
    normals_.assign(static_cast<size_t>(n * 3), 0.f);

    indices_.resize(static_cast<size_t>((width_ - 1) * (height_ - 1) * 6));
    size_t cursor = 0;
    for (int row = 0; row < height_ - 1; ++row) {
        for (int col = 0; col < width_ - 1; ++col) {
            const std::uint32_t a = static_cast<std::uint32_t>(indexOf(col, row));
            const std::uint32_t b = static_cast<std::uint32_t>(indexOf(col + 1, row));
            const std::uint32_t c = static_cast<std::uint32_t>(indexOf(col, row + 1));
            const std::uint32_t d = static_cast<std::uint32_t>(indexOf(col + 1, row + 1));
            // Winding: U right, V down. Triangle pairs face toward +cross(V, U)
            // (toward the camera when the wearer faces the device).
            indices_[cursor++] = a;
            indices_[cursor++] = c;
            indices_[cursor++] = b;
            indices_[cursor++] = b;
            indices_[cursor++] = c;
            indices_[cursor++] = d;
        }
    }

    hashHead_.assign(static_cast<size_t>(kHashBuckets), -1);
    hashNext_.assign(static_cast<size_t>(n), -1);
    buildTopology(spacing_);
    garmentReady_ = false;
}

void ClothSolver::setQuality(int width, int height, float spacing) {
    rebuildBuffers(width, height, spacing);
    initializeGarment(Vec3{-0.18f, 1.45f, -2.0f},
                      Vec3{ 0.18f, 1.45f, -2.0f},
                      Vec3{-0.12f, 0.95f, -2.0f},
                      Vec3{ 0.12f, 0.95f, -2.0f},
                      preferToward_);
}

void ClothSolver::setConfig(const ClothConfig& config) {
    config_ = config;
    config_.damping = clampf(config_.damping, 0.f, 0.95f);
    config_.structuralStiffness = clampf(config_.structuralStiffness, 0.f, 1.f);
    config_.shearStiffness = clampf(config_.shearStiffness, 0.f, 1.f);
    config_.bendStiffness = clampf(config_.bendStiffness, 0.f, 1.f);
    config_.collisionFriction = clampf(config_.collisionFriction, 0.f, 1.f);
    config_.solverIterations = std::max(1, config_.solverIterations);
    config_.substeps = std::max(1, config_.substeps);
    if (config_.particleMass < 1e-4f) config_.particleMass = 1e-4f;
    config_.xpbdCompliance = clampf(config_.xpbdCompliance, 0.f, 5.0e-3f);
}

void ClothSolver::setCapsules(const float* packed, int count) {
    if (packed == nullptr || count <= 0) {
        capsules_.clear();
        return;
    }
    capsules_.resize(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        const float* s = packed + i * 7;
        Capsule& c = capsules_[static_cast<size_t>(i)];
        c.a = Vec3{s[0], s[1], s[2]};
        c.b = Vec3{s[3], s[4], s[5]};
        c.radius = s[6] > 0.f ? s[6] : 0.04f;
    }
}

void ClothSolver::setPhotoAspect(float widthOverHeight) {
    photoAspect_ = widthOverHeight;
}

void ClothSolver::setWind(const Vec3& wind) {
    wind_ = wind;
}

void ClothSolver::setXPBDCompliance(float alpha) {
    config_.xpbdCompliance = clampf(alpha, 0.f, 5.0e-3f);
}

void ClothSolver::enableSelfCollision(bool on) {
    selfCollision_ = on;
}

void ClothSolver::setVolumeEllipsoids(const float* packed, int count) {
    if (packed == nullptr || count <= 0) {
        ellipsoids_.clear();
        return;
    }
    ellipsoids_.resize(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        const float* s = packed + i * 12;
        Ellipsoid& e = ellipsoids_[static_cast<size_t>(i)];
        e.center = Vec3{s[0], s[1], s[2]};
        e.radii = Vec3{std::max(s[3], 0.02f), std::max(s[4], 0.02f), std::max(s[5], 0.02f)};
        e.axisU = normalized(Vec3{s[6], s[7], s[8]}, Vec3{1.f, 0.f, 0.f});
        e.axisV = normalized(Vec3{s[9], s[10], s[11]}, Vec3{0.f, 1.f, 0.f});
        e.axisW = normalized(cross(e.axisU, e.axisV), Vec3{0.f, 0.f, 1.f});
        // Re-orthogonalise V in case the caller packed a non-ortho pair.
        e.axisV = normalized(cross(e.axisW, e.axisU), e.axisV);
    }
}

void ClothSolver::setArmCapsules(const float* packed, int count) {
    if (packed == nullptr || count <= 0) {
        armCapsules_.clear();
        return;
    }
    armCapsules_.resize(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        const float* s = packed + i * 7;
        Capsule& c = armCapsules_[static_cast<size_t>(i)];
        c.a = Vec3{s[0], s[1], s[2]};
        c.b = Vec3{s[3], s[4], s[5]};
        c.radius = s[6] > 0.f ? s[6] : 0.05f;
    }
}

void ClothSolver::setPinMode(PinMode mode) {
    pinMode_ = mode;
}

void ClothSolver::setSizeScale(float scale) {
    sizeScale_ = clampf(scale, 0.72f, 1.40f);
}

void ClothSolver::setFit(float length, float tightness, float drape) {
    lengthScale_ = clampf(length, 0.70f, 1.50f);
    tightness_ = clampf(tightness, 0.55f, 1.60f);
    drape_ = clampf(drape, 0.15f, 2.00f);
}

void ClothSolver::setBodyScale(float scale) {
    bodyScale_ = clampf(scale, 0.80f, 1.25f);
}

void ClothSolver::setParticlePosition(int index, const Vec3& x) {
    if (index < 0 || index >= particleCount()) return;
    Particle& p = particles_[static_cast<size_t>(index)];
    p.x = x;
    p.prev = x;
    positions_[static_cast<size_t>(index * 3 + 0)] = x.x;
    positions_[static_cast<size_t>(index * 3 + 1)] = x.y;
    positions_[static_cast<size_t>(index * 3 + 2)] = x.z;
}

void ClothSolver::buildTopology(float spacing) {
    constraints_.clear();
    constraints_.reserve(static_cast<size_t>(width_ * height_ * 6));

    auto add = [&](int i, int j, float rest, float stiffness, int kind) {
        DistanceConstraint c;
        c.i = i;
        c.j = j;
        c.rest = rest;
        c.stiffness = stiffness;
        c.lambda = 0.f;
        c.kind = kind;
        constraints_.push_back(c);
    };

    // Structural: 4-neighborhood. These are the warp/weft yarns — they carry gravity
    // load and keep the garment from stretching off the body. XPBD at runtime.
    for (int row = 0; row < height_; ++row) {
        for (int col = 0; col < width_; ++col) {
            const int i = indexOf(col, row);
            if (col + 1 < width_) add(i, indexOf(col + 1, row), spacing, 1.f, kStretch);
            if (row + 1 < height_) add(i, indexOf(col, row + 1), spacing, 1.f, kStretch);
        }
    }

    // Shear: cell diagonals. Without them a quad can flatten into a line at constant
    // edge length (a rectangle collapsing into a rhombus of zero area).
    const float diag = spacing * 1.41421356f;
    for (int row = 0; row < height_ - 1; ++row) {
        for (int col = 0; col < width_ - 1; ++col) {
            add(indexOf(col, row), indexOf(col + 1, row + 1), diag, 0.85f, kShear);
            add(indexOf(col + 1, row), indexOf(col, row + 1), diag, 0.85f, kShear);
        }
    }

    // Bending: skip-one springs. A true dihedral constraint resists the angle between
    // two triangles; skip-one distance is a first-order proxy that resists curvature
    // along the grid axes. Rest length is 2*spacing (flat sheet). Lower stiffness lets
    // the garment fold at the waist/elbows instead of remaining a cardboard plane.
    const float bendRest = spacing * 2.f;
    for (int row = 0; row < height_; ++row) {
        for (int col = 0; col + 2 < width_; ++col) {
            add(indexOf(col, row), indexOf(col + 2, row), bendRest, 0.35f, kBend);
        }
    }
    for (int row = 0; row + 2 < height_; ++row) {
        for (int col = 0; col < width_; ++col) {
            add(indexOf(col, row), indexOf(col, row + 2), bendRest, 0.35f, kBend);
        }
    }
}

void ClothSolver::initializeGarment(const Vec3& leftShoulder,
                                    const Vec3& rightShoulder,
                                    const Vec3& leftHip,
                                    const Vec3& rightHip,
                                    const Vec3& preferToward) {
    const bool pants = (pinMode_ == PinMode::Pants);
    const Vec3 shoulderMid = (leftShoulder + rightShoulder) * 0.5f;
    const Vec3 hipMid = (leftHip + rightHip) * 0.5f;

    Vec3 across = pants ? (rightHip - leftHip) : (rightShoulder - leftShoulder);
    float acrossLen = length(across);
    if (acrossLen < 0.05f) {
        across = Vec3{0.36f, 0.f, 0.f};
        acrossLen = 0.36f;
    }
    const Vec3 u = across * (1.f / acrossLen); // left → right

    Vec3 origin = pants ? hipMid : shoulderMid;
    Vec3 down = pants ? ((hipMid + (hipMid - shoulderMid)) - hipMid)
                      : (hipMid - shoulderMid);
    // Pants hang down from the hip line along world -Y mixed with the torso down.
    if (pants) {
        down = Vec3{0.f, -1.f, 0.f};
    }
    float downLen = pants ? 0.55f : length(down);
    if (downLen < 0.05f) {
        down = Vec3{0.f, -0.5f, 0.f};
        downLen = 0.5f;
    }
    const Vec3 v = pants ? down : (down * (1.f / downLen)); // origin → hem

    Vec3 forward = cross(u, Vec3{0.f, 1.f, 0.f});
    const Vec3 torsoOut = cross(u, v * -1.f);
    if (length2(torsoOut) > 1e-6f) {
        forward = torsoOut;
    }
    forward = normalized(forward, Vec3{0.f, 0.f, 1.f});
    preferToward_ = preferToward;
    const Vec3 toViewer = preferToward - origin;
    if (dot(forward, toViewer) < 0.f) {
        forward = forward * -1.f;
    }
    garmentForward_ = forward;

    float halfWidth = acrossLen * 0.5f + 0.04f;
    float lengthV = pants ? downLen : (downLen + 0.06f);

    if (pinMode_ == PinMode::Tank) {
        halfWidth *= 0.78f; // narrower U — tank straps, not full shoulder span
    } else if (pinMode_ == PinMode::Dress) {
        lengthV *= 1.45f; // longer V — hem past the hips
    } else if (pinMode_ == PinMode::Hoodie) {
        lengthV *= 1.12f;
        halfWidth *= 1.06f;
    }

    if (photoAspect_ > 0.05f) {
        const float bodyAspect = (2.f * halfWidth) / std::max(lengthV, 0.05f);
        if (photoAspect_ > bodyAspect) {
            halfWidth *= clampf(photoAspect_ / std::max(bodyAspect, 0.05f), 1.f, 1.6f);
        } else {
            lengthV *= clampf(bodyAspect / photoAspect_, 1.f, 1.6f);
        }
    }

    const float scale = sizeScale_ * bodyScale_;
    halfWidth *= scale * clampf(2.f - tightness_, 0.55f, 1.45f);
    lengthV *= scale * lengthScale_;
    garmentHalfWidth_ = halfWidth;

    const float restInvMass = 1.f / config_.particleMass;
    const float offset = 0.06f;

    for (int row = 0; row < height_; ++row) {
        const float tv = (height_ == 1) ? 0.f : static_cast<float>(row) / static_cast<float>(height_ - 1);
        for (int col = 0; col < width_; ++col) {
            const float tu = (width_ == 1) ? 0.5f : static_cast<float>(col) / static_cast<float>(width_ - 1);
            const Vec3 p = origin
                         + u * ((tu * 2.f - 1.f) * halfWidth)
                         + v * (tv * lengthV)
                         + forward * offset;
            Particle& particle = particles_[static_cast<size_t>(indexOf(col, row))];
            particle.x = p;
            particle.prev = p;
            particle.col = col;
            particle.row = row;
            particle.invMass = restInvMass;
        }
    }

    applyKinematicPins();
    lastLeft_ = pants ? leftHip : leftShoulder;
    lastRight_ = pants ? rightHip : rightShoulder;
    garmentReady_ = true;
    placeKinematicRow(lastLeft_, lastRight_, preferToward, offset);
    recomputeNormals();
}

void ClothSolver::applyKinematicPins() {
    const float restInvMass = 1.f / config_.particleMass;
    for (Particle& p : particles_) p.invMass = restInvMass;

    if (pinMode_ == PinMode::Tank) {
        // Inner ~70% of the shoulder row — straps, not a full collar.
        const int lo = std::max(0, static_cast<int>(width_ * 0.15f));
        const int hi = std::min(width_ - 1, static_cast<int>(width_ * 0.85f));
        for (int col = lo; col <= hi; ++col) {
            particles_[static_cast<size_t>(indexOf(col, 0))].invMass = 0.f;
        }
        return;
    }

    // Tee, hoodie, dress, pants: full top row (shoulders or hip line).
    for (int col = 0; col < width_; ++col) {
        particles_[static_cast<size_t>(indexOf(col, 0))].invMass = 0.f;
    }
}

void ClothSolver::placeKinematicRow(const Vec3& left,
                                    const Vec3& right,
                                    const Vec3& preferToward,
                                    float offset) {
    const Vec3 mid = (left + right) * 0.5f;
    Vec3 across = right - left;
    const float acrossLen = length(across);
    const Vec3 u = (acrossLen > 1e-4f) ? across * (1.f / acrossLen) : Vec3{1.f, 0.f, 0.f};
    preferToward_ = preferToward;
    Vec3 forward = normalized(cross(u, Vec3{0.f, 1.f, 0.f}), garmentForward_);
    const Vec3 toViewer = preferToward - mid;
    if (dot(forward, toViewer) < 0.f) {
        forward = forward * -1.f;
    }
    garmentForward_ = forward;
    const float halfWidth = garmentHalfWidth_;

    auto pinCol = [&](int col) {
        const float tu = (width_ == 1) ? 0.5f : static_cast<float>(col) / static_cast<float>(width_ - 1);
        const Vec3 p = mid + u * ((tu * 2.f - 1.f) * halfWidth) + garmentForward_ * offset;
        Particle& particle = particles_[static_cast<size_t>(indexOf(col, 0))];
        particle.x = p;
        particle.prev = p;
        particle.invMass = 0.f;
    };

    if (pinMode_ == PinMode::Tank) {
        const int lo = std::max(0, static_cast<int>(width_ * 0.15f));
        const int hi = std::min(width_ - 1, static_cast<int>(width_ * 0.85f));
        for (int col = lo; col <= hi; ++col) pinCol(col);
        return;
    }
    for (int col = 0; col < width_; ++col) pinCol(col);
}

void ClothSolver::updateShoulderAnchors(const Vec3& leftShoulder,
                                        const Vec3& rightShoulder,
                                        const Vec3& preferToward) {
    if (!garmentReady_) return;
    lastLeft_ = leftShoulder;
    lastRight_ = rightShoulder;
    placeKinematicRow(leftShoulder, rightShoulder, preferToward, 0.02f);
}

void ClothSolver::step(float dt) {
    if (dt <= kMinDt) return;

    const int substeps = config_.substeps;
    const float rawSub = dt / static_cast<float>(substeps);
    const float subDt = rawSub > kMaxSubstepDt ? kMaxSubstepDt : (rawSub < kMinDt ? kMinDt : rawSub);
    const float dt2 = subDt * subDt;
    const Vec3 gravity{0.f, config_.gravityY, 0.f};
    const float velDamp = 1.f - config_.damping;
    const float windMag = length(wind_);
    simTime_ += subDt * static_cast<float>(substeps);

    for (int s = 0; s < substeps; ++s) {
        // 1. Verlet integrate with gravity + world-space wind. Velocity is (x - prev);
        //    damping is applied to that implicit velocity before the position is advanced.
        //    Kinematic particles (invMass == 0) keep the position written by anchors.
        int pi = 0;
        for (Particle& p : particles_) {
            if (p.invMass <= 0.f) {
                ++pi;
                continue;
            }
            const Vec3 vel = (p.x - p.prev) * velDamp;
            p.prev = p.x;
            Vec3 acc = gravity + wind_;
            if (windMag > 1e-6f) {
                // Mild flutter so a constant wind does not look like a wind-tunnel slab.
                const float n = (hash01(pi, simTime_ + static_cast<float>(s) * 0.17f) - 0.5f) * 2.f;
                acc += Vec3{n * 0.15f * windMag, n * 0.05f * windMag, n * 0.12f * windMag};
            }
            p.x += vel + acc * dt2;
            ++pi;
        }

        // Reset XPBD lambdas each substep (Macklin / Müller 2016).
        for (DistanceConstraint& c : constraints_) c.lambda = 0.f;

        // 2–4. Project stretch (XPBD), shear, bend, then collide. Repeating the whole
        //    stack several times lets a locally-stiff constraint propagate (Gauss–Seidel).
        //    Collision last so we don't project back into the body.
        for (int it = 0; it < config_.solverIterations; ++it) {
            projectDistanceConstraints(subDt);
            collideCapsules();
            collideEllipsoids();
        }
        collideSelf();
        applyArmPins();
    }

    recomputeNormals();
}

void ClothSolver::projectDistanceConstraints(float subDt) {
    const float kStruct = clampf(config_.structuralStiffness * tightness_, 0.05f, 1.f);
    const float kShear = config_.shearStiffness;
    const float kBend = clampf(config_.bendStiffness * drape_, 0.02f, 1.f);
    const float alpha = config_.xpbdCompliance;
    const float dt2 = std::max(subDt * subDt, 1e-8f);
    const float atilde = alpha / dt2;

    for (DistanceConstraint& c : constraints_) {
        Particle& a = particles_[static_cast<size_t>(c.i)];
        Particle& b = particles_[static_cast<size_t>(c.j)];
        const float w = a.invMass + b.invMass;
        if (w <= 0.f) continue;

        const Vec3 delta = b.x - a.x;
        const float len2 = length2(delta);
        if (len2 < kEps) continue;
        const float len = sqrtf(len2);

        if (c.kind == kStretch) {
            // XPBD stretch. C = |x_j - x_i| - rest.
            // Δλ = (−C − α̃ λ) / (w + α̃). α = 0 → full correction (hard).
            // Structural stiffness still scales Δλ so fabric presets (silk vs denim)
            // remain distinct even at a fixed iteration count.
            const float C = len - c.rest;
            const float denom = w + atilde;
            if (denom <= kEps) continue;
            float dlam = (-C - atilde * c.lambda) / denom;
            dlam *= kStruct;
            // Clamp the resulting position step, not λ itself — invMass is ~50 for
            // a 20 g particle, so a raw |Δλ| clamp of rest-length would still fling.
            const float maxCorr = spacing_ * 0.5f;
            const float maxInv = std::max(std::max(a.invMass, b.invMass), 1e-6f);
            const float maxDlam = maxCorr / maxInv;
            dlam = clampf(dlam, -maxDlam, maxDlam);
            c.lambda += dlam;
            const Vec3 n = delta * (1.f / len);
            // XPBD: x_i += w_i ∇C_i Δλ with ∇C_i = -n, ∇C_j = +n, n = (x_j-x_i)/|·|.
            if (a.invMass > 0.f) a.x -= n * (a.invMass * dlam);
            if (b.invMass > 0.f) b.x += n * (b.invMass * dlam);
            continue;
        }

        float k = (c.kind == kShear) ? kShear : kBend;
        if (k <= 0.f) continue;
        const float corr = k * (len - c.rest) / (len * w);
        const Vec3 n = delta * corr;
        if (a.invMass > 0.f) a.x += n * a.invMass;
        if (b.invMass > 0.f) b.x -= n * b.invMass;
    }
}

void ClothSolver::collideCapsules() {
    if (capsules_.empty()) return;
    const float friction = config_.collisionFriction;

    for (Particle& p : particles_) {
        if (p.invMass <= 0.f) continue;
        for (const Capsule& cap : capsules_) {
            const Vec3 closest = closestPointOnSegment(p.x, cap.a, cap.b);
            Vec3 d = p.x - closest;
            const float dist2 = length2(d);
            const float r = cap.radius;
            if (dist2 >= r * r) continue;

            const float dist = dist2 > kEps ? sqrtf(dist2) : 0.f;
            Vec3 n;
            if (dist > 1e-5f) {
                n = d * (1.f / dist);
            } else {
                n = Vec3{0.f, 1.f, 0.f};
            }
            const Vec3 resolved = closest + n * r;

            const Vec3 delta = resolved - p.prev;
            const float vn = dot(delta, n);
            const Vec3 nComp = n * vn;
            const Vec3 tComp = delta - nComp;
            p.x = resolved;
            p.prev = resolved - (nComp + tComp * (1.f - friction));
        }
    }
}

void ClothSolver::collideEllipsoids() {
    if (ellipsoids_.empty()) return;
    const float friction = config_.collisionFriction;

    for (Particle& p : particles_) {
        if (p.invMass <= 0.f) continue;
        for (const Ellipsoid& e : ellipsoids_) {
            const Vec3 d = p.x - e.center;
            const float lx = dot(d, e.axisU) / e.radii.x;
            const float ly = dot(d, e.axisV) / e.radii.y;
            const float lz = dot(d, e.axisW) / e.radii.z;
            const float q = lx * lx + ly * ly + lz * lz;
            if (q >= 1.f || q < kEps) {
                if (q >= 1.f) continue;
                // Degenerate: particle at centre. Push along world up.
                const Vec3 resolved = e.center + Vec3{0.f, e.radii.y, 0.f};
                p.x = resolved;
                p.prev = resolved;
                continue;
            }
            // Project onto the ellipsoid surface along the implicit-function gradient.
            const float s = 1.f / sqrtf(q);
            const Vec3 local{lx * s * e.radii.x, ly * s * e.radii.y, lz * s * e.radii.z};
            const Vec3 resolved = e.center
                                + e.axisU * local.x
                                + e.axisV * local.y
                                + e.axisW * local.z;
            Vec3 n = resolved - e.center;
            n = normalized(n, Vec3{0.f, 1.f, 0.f});
            const Vec3 delta = resolved - p.prev;
            const float vn = dot(delta, n);
            const Vec3 nComp = n * vn;
            const Vec3 tComp = delta - nComp;
            p.x = resolved;
            p.prev = resolved - (nComp + tComp * (1.f - friction));
        }
    }
}

void ClothSolver::collideSelf() {
    const int n = particleCount();
    if (!selfCollision_ || n > kSelfCollisionSkipN || n < 4) return;

    const float minDist = 0.7f * spacing_;
    const float minDist2 = minDist * minDist;
    const float invCell = 1.f / std::max(minDist, 1e-4f);

    std::fill(hashHead_.begin(), hashHead_.end(), -1);
    if (static_cast<int>(hashNext_.size()) < n) hashNext_.assign(static_cast<size_t>(n), -1);

    auto cellHash = [&](int ix, int iy, int iz) {
        // Triple coprime hash → bucket. Enough for a 24–32 grid.
        const int h = ix * 73856093 ^ iy * 19349663 ^ iz * 83492791;
        return wrapBucket(h);
    };

    for (int i = 0; i < n; ++i) {
        const Vec3& x = particles_[static_cast<size_t>(i)].x;
        const int ix = static_cast<int>(floorf(x.x * invCell));
        const int iy = static_cast<int>(floorf(x.y * invCell));
        const int iz = static_cast<int>(floorf(x.z * invCell));
        const int b = cellHash(ix, iy, iz);
        hashNext_[static_cast<size_t>(i)] = hashHead_[static_cast<size_t>(b)];
        hashHead_[static_cast<size_t>(b)] = i;
    }

    for (int i = 0; i < n; ++i) {
        Particle& a = particles_[static_cast<size_t>(i)];
        if (a.invMass <= 0.f) continue;
        const int ix = static_cast<int>(floorf(a.x.x * invCell));
        const int iy = static_cast<int>(floorf(a.x.y * invCell));
        const int iz = static_cast<int>(floorf(a.x.z * invCell));
        for (int dz = -1; dz <= 1; ++dz) {
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    const int b = cellHash(ix + dx, iy + dy, iz + dz);
                    for (int j = hashHead_[static_cast<size_t>(b)]; j >= 0; j = hashNext_[static_cast<size_t>(j)]) {
                        if (j <= i) continue;
                        Particle& o = particles_[static_cast<size_t>(j)];
                        // Skip adjacent (incl. diagonal) grid neighbours — those are
                        // already held by stretch/shear rest lengths.
                        const int dc = a.col - o.col;
                        const int dr = a.row - o.row;
                        if (dc <= 1 && dc >= -1 && dr <= 1 && dr >= -1) continue;
                        Vec3 d = o.x - a.x;
                        const float d2 = length2(d);
                        if (d2 >= minDist2 || d2 < kEps) continue;
                        const float dist = sqrtf(d2);
                        const float pen = minDist - dist;
                        const Vec3 n = d * (1.f / dist);
                        const float wa = a.invMass;
                        const float wb = o.invMass;
                        const float wsum = wa + wb;
                        if (wsum <= 0.f) continue;
                        const Vec3 corr = n * (pen / wsum);
                        if (wa > 0.f) a.x -= corr * wa;
                        if (wb > 0.f) o.x += corr * wb;
                    }
                }
            }
        }
    }
}

void ClothSolver::applyArmPins() {
    // Sleeve approximation: left/right side-column particles (upper half of the
    // sheet) are softly attracted toward the matching upper-arm capsule. There is
    // no second sleeve mesh — this only keeps the sheet from floating off the arms.
    if (armCapsules_.empty()) return;
    if (pinMode_ == PinMode::Pants) return;

    const int rowMax = std::max(1, height_ / 2);
    const float kSoft = 0.18f;
    const int nArm = static_cast<int>(armCapsules_.size());

    auto attract = [&](int col, const Capsule& cap) {
        for (int row = 1; row < rowMax; ++row) {
            Particle& p = particles_[static_cast<size_t>(indexOf(col, row))];
            if (p.invMass <= 0.f) continue;
            const Vec3 closest = closestPointOnSegment(p.x, cap.a, cap.b);
            Vec3 d = p.x - closest;
            const float dist = length(d);
            const float target = cap.radius + spacing_ * 0.5f;
            Vec3 n = (dist > 1e-5f) ? d * (1.f / dist) : Vec3{0.f, 0.f, 1.f};
            const Vec3 goal = closest + n * target;
            p.x += (goal - p.x) * kSoft;
        }
    };

    // First capsule = anatomical left (col 0), second = right (last col). If only
    // one is packed, both sides use it.
    attract(0, armCapsules_[0]);
    attract(width_ - 1, armCapsules_[static_cast<size_t>(nArm > 1 ? 1 : 0)]);
}

void ClothSolver::recomputeNormals() {
    for (int row = 0; row < height_; ++row) {
        const int rowM = row > 0 ? row - 1 : row;
        const int rowP = row + 1 < height_ ? row + 1 : row;
        for (int col = 0; col < width_; ++col) {
            const int colM = col > 0 ? col - 1 : col;
            const int colP = col + 1 < width_ ? col + 1 : col;
            const Vec3& left = particles_[static_cast<size_t>(indexOf(colM, row))].x;
            const Vec3& right = particles_[static_cast<size_t>(indexOf(colP, row))].x;
            const Vec3& up = particles_[static_cast<size_t>(indexOf(col, rowM))].x;
            const Vec3& down = particles_[static_cast<size_t>(indexOf(col, rowP))].x;
            const Vec3 du = right - left;
            const Vec3 dv = down - up;
            const Vec3 nrm = normalized(cross(dv, du), Vec3{0.f, 0.f, 1.f});
            const int i = indexOf(col, row);
            normals_[static_cast<size_t>(i * 3 + 0)] = nrm.x;
            normals_[static_cast<size_t>(i * 3 + 1)] = nrm.y;
            normals_[static_cast<size_t>(i * 3 + 2)] = nrm.z;
            positions_[static_cast<size_t>(i * 3 + 0)] = particles_[static_cast<size_t>(i)].x.x;
            positions_[static_cast<size_t>(i * 3 + 1)] = particles_[static_cast<size_t>(i)].x.y;
            positions_[static_cast<size_t>(i * 3 + 2)] = particles_[static_cast<size_t>(i)].x.z;
        }
    }
}

} // namespace fitty
