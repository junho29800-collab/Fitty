#include "ClothSolver.hpp"

#include <algorithm>
#include <cstring>

namespace fitty {
namespace {

constexpr float kMinDt = 1e-5f;
constexpr float kMaxSubstepDt = 1.f / 30.f;
constexpr float kEps = 1e-8f;

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

} // namespace

ClothSolver::ClothSolver(int width, int height, float spacing)
    : width_(std::max(2, width)),
      height_(std::max(2, height)),
      spacing_(spacing > 1e-4f ? spacing : 0.02f) {
    const int n = width_ * height_;
    particles_.resize(static_cast<size_t>(n));
    positions_.assign(static_cast<size_t>(n * 3), 0.f);
    normals_.assign(static_cast<size_t>(n * 3), 0.f);

    // Two triangles per cell.
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

    buildTopology(spacing_);

    // Default standing T-pose garment ~2 m in front of the origin so the Simulator
    // path has a well-defined rest pose before ARKit delivers a skeleton.
    initializeGarment(Vec3{-0.18f, 1.45f, -2.0f},
                      Vec3{ 0.18f, 1.45f, -2.0f},
                      Vec3{-0.12f, 0.95f, -2.0f},
                      Vec3{ 0.12f, 0.95f, -2.0f},
                      Vec3{ 0.f, 1.5f, 0.f});
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

void ClothSolver::buildTopology(float spacing) {
    constraints_.clear();
    constraints_.reserve(static_cast<size_t>(width_ * height_ * 6));

    auto add = [&](int i, int j, float rest, float stiffness) {
        DistanceConstraint c;
        c.i = i;
        c.j = j;
        c.rest = rest;
        c.stiffness = stiffness;
        constraints_.push_back(c);
    };

    // Structural: 4-neighborhood. These are the warp/weft yarns — they carry gravity
    // load and keep the garment from stretching off the body.
    for (int row = 0; row < height_; ++row) {
        for (int col = 0; col < width_; ++col) {
            const int i = indexOf(col, row);
            if (col + 1 < width_) add(i, indexOf(col + 1, row), spacing, 1.f /* structural */);
            if (row + 1 < height_) add(i, indexOf(col, row + 1), spacing, 1.f /* structural */);
        }
    }

    // Shear: cell diagonals. Without them a quad can flatten into a line at constant
    // edge length (a rectangle collapsing into a rhombus of zero area).
    const float diag = spacing * 1.41421356f;
    for (int row = 0; row < height_ - 1; ++row) {
        for (int col = 0; col < width_ - 1; ++col) {
            add(indexOf(col, row), indexOf(col + 1, row + 1), diag, 0.85f);
            add(indexOf(col + 1, row), indexOf(col, row + 1), diag, 0.85f);
        }
    }

    // Bending: skip-one springs. A true dihedral constraint resists the angle between
    // two triangles; skip-one distance is a first-order proxy that resists curvature
    // along the grid axes. Rest length is 2*spacing (flat sheet). Lower stiffness lets
    // the garment fold at the waist/elbows instead of remaining a cardboard plane.
    const float bendRest = spacing * 2.f;
    for (int row = 0; row < height_; ++row) {
        for (int col = 0; col + 2 < width_; ++col) {
            add(indexOf(col, row), indexOf(col + 2, row), bendRest, 0.35f);
        }
    }
    for (int row = 0; row + 2 < height_; ++row) {
        for (int col = 0; col < width_; ++col) {
            add(indexOf(col, row), indexOf(col, row + 2), bendRest, 0.35f);
        }
    }

    (void)spacing;
}

void ClothSolver::initializeGarment(const Vec3& leftShoulder,
                                    const Vec3& rightShoulder,
                                    const Vec3& leftHip,
                                    const Vec3& rightHip,
                                    const Vec3& preferToward) {
    const Vec3 shoulderMid = (leftShoulder + rightShoulder) * 0.5f;
    const Vec3 hipMid = (leftHip + rightHip) * 0.5f;

    Vec3 across = rightShoulder - leftShoulder;
    float acrossLen = length(across);
    if (acrossLen < 0.05f) {
        across = Vec3{0.36f, 0.f, 0.f};
        acrossLen = 0.36f;
    }
    const Vec3 u = across * (1.f / acrossLen); // left → right

    Vec3 down = hipMid - shoulderMid;
    float downLen = length(down);
    if (downLen < 0.05f) {
        down = Vec3{0.f, -0.5f, 0.f};
        downLen = 0.5f;
    }
    const Vec3 v = down * (1.f / downLen); // shoulder → hip

    // Chest-forward: perpendicular to the torso plane, pointing toward the camera
    // when the wearer faces the device. Fallback +Z if the skeleton is degenerate.
    Vec3 forward = cross(u, Vec3{0.f, 1.f, 0.f});
    // Prefer a forward that also agrees with the torso plane (u × -v, since v is down).
    const Vec3 torsoOut = cross(u, v * -1.f); // u × up-along-spine
    if (length2(torsoOut) > 1e-6f) {
        forward = torsoOut;
    }
    forward = normalized(forward, Vec3{0.f, 0.f, 1.f});
    preferToward_ = preferToward;
    // Sit on the camera-facing side of the torso (between wearer and device).
    const Vec3 toViewer = preferToward - shoulderMid;
    if (dot(forward, toViewer) < 0.f) {
        forward = forward * -1.f;
    }
    garmentForward_ = forward;

    // Extend a bit past the shoulder joints so the patch wraps toward the deltoids,
    // and a bit past the hips so the hem has length to drape.
    float halfWidth = acrossLen * 0.5f + 0.04f;
    float lengthV = downLen + 0.06f;
    // Optional photo-aspect fit: a wide shirt isn't squashed into a square, a tunic
    // isn't cropped to a tee. Rest lengths stay at construction spacing (fitted slack).
    if (photoAspect_ > 0.05f) {
        const float bodyAspect = (2.f * halfWidth) / std::max(lengthV, 0.05f);
        if (photoAspect_ > bodyAspect) {
            halfWidth *= clampf(photoAspect_ / std::max(bodyAspect, 0.05f), 1.f, 1.6f);
        } else {
            lengthV *= clampf(bodyAspect / photoAspect_, 1.f, 1.6f);
        }
    }
    garmentHalfWidth_ = halfWidth;

    const float restInvMass = 1.f / config_.particleMass;
    const float offset = 0.06f; // meters in front of the chest so we don't spawn inside.

    for (int row = 0; row < height_; ++row) {
        const float tv = (height_ == 1) ? 0.f : static_cast<float>(row) / static_cast<float>(height_ - 1);
        for (int col = 0; col < width_; ++col) {
            const float tu = (width_ == 1) ? 0.5f : static_cast<float>(col) / static_cast<float>(width_ - 1);
            const Vec3 p = shoulderMid
                         + u * ((tu * 2.f - 1.f) * halfWidth)
                         + v * (tv * lengthV)
                         + forward * offset;
            Particle& particle = particles_[static_cast<size_t>(indexOf(col, row))];
            particle.x = p;
            particle.prev = p;
            // Top row is sewn to the shoulder line (kinematic). Everything else is dynamic
            // so gravity + collision can drape the garment over the torso capsules.
            particle.invMass = (row == 0) ? 0.f : restInvMass;
        }
    }

    // Rest lengths stay at the construction spacing so the fabric has a defined rest
    // size independent of the wearer's current pose. A larger torso therefore starts
    // slightly pre-stretched (a "fitted" shirt); a smaller torso starts with slack.
    garmentReady_ = true;
    applyKinematicTopRow();
    recomputeNormals();
}

void ClothSolver::updateShoulderAnchors(const Vec3& leftShoulder,
                                        const Vec3& rightShoulder,
                                        const Vec3& preferToward) {
    if (!garmentReady_) return;

    const Vec3 mid = (leftShoulder + rightShoulder) * 0.5f;
    Vec3 across = rightShoulder - leftShoulder;
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
    const float offset = 0.02f; // sit just in front of the shoulder capsules

    for (int col = 0; col < width_; ++col) {
        const float tu = (width_ == 1) ? 0.5f : static_cast<float>(col) / static_cast<float>(width_ - 1);
        const Vec3 p = mid + u * ((tu * 2.f - 1.f) * halfWidth) + garmentForward_ * offset;
        Particle& particle = particles_[static_cast<size_t>(indexOf(col, 0))];
        particle.x = p;
        particle.prev = p; // zero implicit velocity — anchors shouldn't slingshot the hem
        particle.invMass = 0.f;
    }
}

void ClothSolver::applyKinematicTopRow() {
    for (int col = 0; col < width_; ++col) {
        particles_[static_cast<size_t>(indexOf(col, 0))].invMass = 0.f;
    }
}

void ClothSolver::step(float dt) {
    if (dt <= kMinDt) return;

    const int substeps = config_.substeps;
    const float rawSub = dt / static_cast<float>(substeps);
    const float subDt = rawSub > kMaxSubstepDt ? kMaxSubstepDt : (rawSub < kMinDt ? kMinDt : rawSub);
    const float dt2 = subDt * subDt;
    const Vec3 gravity{0.f, config_.gravityY, 0.f};
    const float velDamp = 1.f - config_.damping;

    for (int s = 0; s < substeps; ++s) {
        // 1. Verlet integrate with gravity. Velocity is (x - prev); damping is applied
        //    to that implicit velocity before the position is advanced. Kinematic
        //    particles (invMass == 0) keep the position written by updateShoulderAnchors.
        for (Particle& p : particles_) {
            if (p.invMass <= 0.f) continue;
            const Vec3 vel = (p.x - p.prev) * velDamp;
            p.prev = p.x;
            p.x += vel + gravity * dt2;
        }

        // 2–4. Project stretch, shear, bend, then collide. Repeating the whole stack
        //    several times lets a locally-stiff constraint propagate along the sheet
        //    (Gauss–Seidel). Collision last so we don't project back into the body.
        for (int it = 0; it < config_.solverIterations; ++it) {
            projectDistanceConstraints();
            collideCapsules();
        }
    }

    recomputeNormals();
}

void ClothSolver::projectDistanceConstraints() {
    const float kStruct = config_.structuralStiffness;
    const float kShear = config_.shearStiffness;
    const float kBend = config_.bendStiffness;

    for (const DistanceConstraint& c : constraints_) {
        Particle& a = particles_[static_cast<size_t>(c.i)];
        Particle& b = particles_[static_cast<size_t>(c.j)];
        const float w = a.invMass + b.invMass;
        if (w <= 0.f) continue;

        const Vec3 delta = b.x - a.x;
        const float len = length(delta);
        if (len < kEps) continue;

        // Pick the [0,1] weight that matches this constraint's role. The stored
        // stiffness on the constraint is a rest-time tag; runtime config can retune
        // all structural / shear / bend groups without rebuilding topology.
        float k = c.stiffness;
        if (c.stiffness > 0.9f) k = kStruct;
        else if (c.stiffness > 0.5f) k = kShear;
        else k = kBend;
        if (k <= 0.f) continue;

        // Classic PBD: move each particle along the constraint gradient in proportion
        // to inverse mass. k is applied directly; with ~12 iterations this is close
        // to a hard constraint for k≈1.
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
                // Degenerate: particle sits on the axis. Push along world up so we
                // still resolve instead of NaNing.
                n = Vec3{0.f, 1.f, 0.f};
            }
            const Vec3 resolved = closest + n * r;

            // Tangential damping: keep the normal separation, bleed sliding. Verlet
            // velocity next step is (x - prev), so we rewrite prev to encode the
            // desired post-collision velocity.
            const Vec3 delta = resolved - p.prev;
            const float vn = dot(delta, n);
            const Vec3 nComp = n * vn;
            const Vec3 tComp = delta - nComp;
            p.x = resolved;
            p.prev = resolved - (nComp + tComp * (1.f - friction));
        }
    }
}

void ClothSolver::recomputeNormals() {
    // Grid-tangent normals. For interior vertices this is equivalent to averaging
    // the two incident edge tangents; boundaries one-side the difference.
    // n = normalize(down × right) so the front of a camera-facing wearer points out.
    const int n = particleCount();
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
    (void)n;
}

} // namespace fitty
