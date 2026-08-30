#pragma once

// ClothSolver — explicit Position Based Dynamics (PBD) for a regular garment grid.
//
// Unit system: meters, seconds. Positions live in ARKit world space (Y-up, right-handed),
// the same frame as ARBodyAnchor.transform * skeleton.modelTransform(for:). Gravity is
// (0, -9.81, 0) m/s². Do not mix model-space joint offsets in here.
//
// Why PBD (Müller et al. 2007) instead of implicit FEM:
//   * Unconditionally stable with a cheap projection loop — required for 60 Hz on-device.
//   * Constraint stiffness is a [0,1] projection weight, not a Young's modulus. Higher
//     iteration counts make the same stiffness feel more rigid (classic PBD limitation).
//   * Verlet integration stores velocity implicitly as (x - x_prev), so we never integrate
//     an explicit v that can explode when a constraint suddenly becomes satisfied.
//
// Constraint roles:
//   * Structural (grid edges)  — resist stretch. Fabric should not grow under gravity.
//   * Shear (grid diagonals)   — resist parallelogram collapse in the plane of the cloth.
//   * Bending (skip-one edges) — resist folding. Softer than stretch so the sheet drapes
//     rather than acting like a stiff plate. Skip-one springs are cheaper and more stable
//     than dihedral constraints at this particle count; they do not encode a rest angle,
//     which is acceptable for a thin garment patch.
//
// Collision: finite capsules (segment + radius) built from ARSkeleton3D joints. A point
// inside a capsule is pushed to the surface along the shortest vector. Capsules are a
// cheap inner approximation of the body; they will not capture chest/breast/glute detail
// (an SDF or mesh collider is the next step).
//
// Threading: this class is NOT thread-safe. The ObjC++ bridge owns a serial queue and
// must call every method from that one thread. No exceptions are thrown.

#include <cmath>
#include <cstdint>
#include <vector>

namespace fitty {

struct Vec3 {
    float x = 0.f;
    float y = 0.f;
    float z = 0.f;

    Vec3() = default;
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

inline Vec3 operator+(const Vec3& a, const Vec3& b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vec3 operator-(const Vec3& a, const Vec3& b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline Vec3 operator*(const Vec3& a, float s) { return {a.x * s, a.y * s, a.z * s}; }
inline Vec3 operator*(float s, const Vec3& a) { return a * s; }
inline Vec3& operator+=(Vec3& a, const Vec3& b) { a.x += b.x; a.y += b.y; a.z += b.z; return a; }
inline Vec3& operator-=(Vec3& a, const Vec3& b) { a.x -= b.x; a.y -= b.y; a.z -= b.z; return a; }

inline float dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

inline float length2(const Vec3& a) { return dot(a, a); }

inline float length(const Vec3& a) {
    const float l2 = length2(a);
    return l2 > 0.f ? sqrtf(l2) : 0.f;
}

inline Vec3 cross(const Vec3& a, const Vec3& b) {
    return {a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x};
}

inline Vec3 normalized(const Vec3& a, const Vec3& fallback) {
    const float l2 = length2(a);
    if (l2 < 1e-12f) return fallback;
    return a * (1.f / sqrtf(l2));
}

struct Capsule {
    Vec3 a;
    Vec3 b;
    float radius = 0.05f;
};

struct ClothConfig {
    float particleMass = 0.02f;          // kg. Ratios matter for mixed kinematic/dynamic; gravity is mass-independent in Verlet.
    float damping = 0.04f;               // dimensionless velocity bleed per substep (0 = none, 1 = freeze).
    float gravityY = -9.81f;             // m/s², ARKit Y-up.
    float structuralStiffness = 1.00f;   // [0,1] stretch projection weight.
    float shearStiffness = 0.85f;        // [0,1] in-plane shear.
    float bendStiffness = 0.35f;         // [0,1] skip-one bending; keep below stretch so the sheet folds.
    float collisionFriction = 0.35f;     // [0,1] tangential damping against capsules.
    int solverIterations = 12;           // projections per substep. 8–16 is the useful range on-device.
    int substeps = 2;                    // fixed-dt slices per call to step().
};

class ClothSolver {
public:
    // width = columns (U, across the chest), height = rows (V, shoulder → hip).
    // spacing = rest distance between adjacent particles in meters (fabric rest length).
    ClothSolver(int width, int height, float spacing);
    ~ClothSolver() = default;

    ClothSolver(const ClothSolver&) = delete;
    ClothSolver& operator=(const ClothSolver&) = delete;

    void setConfig(const ClothConfig& config);
    const ClothConfig& config() const { return config_; }

    // Packed capsules: 7 floats each (ax,ay,az, bx,by,bz, radius). Copied internally.
    void setCapsules(const float* packed, int count);

    // Place a rectangular garment patch spanning shoulders → hips, offset slightly along
    // the chest-forward axis so it starts in front of the torso and drapes under gravity
    // + collision rather than spawning inside the body. Top-row particles become kinematic
    // anchors that follow the shoulder line (updated via updateShoulderAnchors).
    //
    // All four points are ARKit world-space meters.
    void initializeGarment(const Vec3& leftShoulder,
                           const Vec3& rightShoulder,
                           const Vec3& leftHip,
                           const Vec3& rightHip,
                           const Vec3& preferToward);

    // Reposition the kinematic top row between the current shoulder world positions.
    // Call every frame before step() so the garment stays attached as the body moves.
    void updateShoulderAnchors(const Vec3& leftShoulder,
                               const Vec3& rightShoulder,
                               const Vec3& preferToward);

    // Advance the simulation. dt is the *frame* delta in seconds; internally split into
    // `substeps` slices of dt/substeps, each clamped to (0, 1/30] to keep Verlet stable
    // when the render thread hitchs.
    void step(float dt);

    // Tightly packed xyz (3 * particleCount floats). Pointers remain valid until the next
    // initializeGarment(). Never returns null after construction.
    const float* positions() const { return positions_.data(); }
    const float* normals() const { return normals_.data(); }
    int particleCount() const { return width_ * height_; }
    int width() const { return width_; }
    int height() const { return height_; }

    const std::uint32_t* indices() const { return indices_.data(); }
    int indexCount() const { return static_cast<int>(indices_.size()); }

private:
    struct Particle {
        Vec3 x;
        Vec3 prev;
        float invMass = 1.f; // 0 = kinematic (infinite mass).
    };

    struct DistanceConstraint {
        int i = 0;
        int j = 0;
        float rest = 0.f;
        float stiffness = 1.f; // [0,1]
    };

    int indexOf(int col, int row) const { return row * width_ + col; }

    void buildTopology(float spacing);
    void projectDistanceConstraints();
    void collideCapsules();
    void recomputeNormals();
    void applyKinematicTopRow();

    int width_ = 0;
    int height_ = 0;
    float spacing_ = 0.02f;
    ClothConfig config_{};

    std::vector<Particle> particles_;
    std::vector<float> positions_;          // packed xyz, preallocated
    std::vector<float> normals_;            // packed xyz, preallocated
    std::vector<std::uint32_t> indices_;    // triangle list, preallocated
    std::vector<DistanceConstraint> constraints_;
    std::vector<Capsule> capsules_;

    // Cached garment frame so the top row can be re-anchored without a full reset.
    Vec3 garmentForward_{0.f, 0.f, 1.f};
    Vec3 preferToward_{0.f, 1.5f, 0.f};
    float garmentHalfWidth_ = 0.2f;
    bool garmentReady_ = false;
};

} // namespace fitty
