#pragma once

// ClothSolver — Position Based Dynamics (PBD) + XPBD stretch on a regular garment grid.
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
// XPBD stretch (Macklin / Müller 2016):
//   Structural (warp/weft) constraints use extended PBD with compliance α
//   (setXPBDCompliance). The multiplier is α̃ = α / Δt². Position correction is
//     Δλ = (−C − α̃ λ) / (w + α̃),  x += w_i ∇C Δλ
//   with λ accumulated across Gauss–Seidel iterations of a substep and reset each
//   substep. α = 0 recovers a hard constraint (iteration-count independent when
//   the system is solvable). α > 0 makes stretch stiffness a material property
//   instead of an iteration-count artifact. Shear and bend stay classic PBD so
//   drape still folds. Keep α in roughly [0, 5e-4]; larger values are silk-floppy
//   and remain stable at dt = 1/30.
//
// Constraint roles:
//   * Structural (grid edges)  — XPBD stretch. Fabric should not grow under gravity.
//   * Shear (grid diagonals)   — classic PBD. Resist parallelogram collapse.
//   * Bending (skip-one edges) — classic PBD. Softer than stretch so the sheet drapes.
//
// Collision:
//   * Finite capsules (segment + radius) from ARSkeleton3D joints.
//   * Volume ellipsoids (chest + hip) so the sheet sits on the torso, not in it.
//   * Self-collision via a spatial hash: non-adjacent particles closer than
//     0.7 * spacing are separated. Skipped when particle count > 1600.
//   * Arm pins: left/right side-column particles are softly attracted to upper-arm
//     capsules. This is a SLEEVE APPROXIMATION — there is no second sleeve mesh.
//
// Pinning (PinMode):
//   Tee / Hoodie — kinematic shoulder (top) row.
//   Tank         — kinematic shoulder row, narrower U (0.78× half-width).
//   Dress        — kinematic shoulder row, longer V (1.45×).
//   Pants        — kinematic HIP row (row 0 placed on the hip line, hanging down).
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

// Oriented ellipsoid. Packed as 12 floats:
//   cx, cy, cz, rx, ry, rz, ux, uy, uz, vx, vy, vz
// where (u, v, u×v) is the local frame and (rx, ry, rz) are half-axes in meters.
struct Ellipsoid {
    Vec3 center;
    Vec3 radii{0.12f, 0.10f, 0.10f};
    Vec3 axisU{1.f, 0.f, 0.f};
    Vec3 axisV{0.f, 1.f, 0.f};
    Vec3 axisW{0.f, 0.f, 1.f};
};

enum class PinMode : int {
    Tee = 0,
    Tank = 1,
    Hoodie = 2,
    Dress = 3,
    Pants = 4
};

struct ClothConfig {
    float particleMass = 0.02f;          // kg. Ratios matter for mixed kinematic/dynamic; gravity is mass-independent in Verlet.
    float damping = 0.04f;               // dimensionless velocity bleed per substep (0 = none, 1 = freeze).
    float gravityY = -9.81f;             // m/s², ARKit Y-up.
    float structuralStiffness = 1.00f;   // [0,1] stretch projection weight (classic PBD path / XPBD mix).
    float shearStiffness = 0.85f;        // [0,1] in-plane shear.
    float bendStiffness = 0.35f;         // [0,1] skip-one bending; keep below stretch so the sheet folds.
    float collisionFriction = 0.35f;     // [0,1] tangential damping against capsules.
    int solverIterations = 12;           // projections per substep. 8–16 is the useful range on-device.
    int substeps = 2;                    // fixed-dt slices per call to step().
    float xpbdCompliance = 1.0e-5f;      // stretch α (m/N). 0 = hard XPBD. Silk ~2e-4, denim ~1e-6.
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

    // Optional width/height of the isolated garment photo. <= 0 keeps body-only sizing.
    // A wide shirt (aspect > 1) grows across the shoulders; a long tunic grows toward the hips.
    // Clamped so the patch stays within 1.6× the skeleton-fitted size. Call before initializeGarment.
    void setPhotoAspect(float widthOverHeight);
    float photoAspect() const { return photoAspect_; }

    // World-space wind in m/s², applied in Verlet as extra acceleration plus mild
    // per-particle hash noise (amplitude ~0.15 * |wind|).
    void setWind(const Vec3& wind);
    Vec3 wind() const { return wind_; }

    // XPBD stretch compliance α. See file header.
    void setXPBDCompliance(float alpha);

    // Cheap self-collision. Off or huge particle counts skip the hash.
    void enableSelfCollision(bool on);
    bool selfCollisionEnabled() const { return selfCollision_; }

    // Packed ellipsoids: 12 floats each (see Ellipsoid). Chest + hip volumes.
    void setVolumeEllipsoids(const float* packed, int count);

    // Upper-arm capsules (7 floats each) for the sleeve approximation.
    void setArmCapsules(const float* packed, int count);

    // Rebuild the grid (Low / Med / High quality). Restarts the default T-pose
    // garment; the Swift side should call initializeGarment with the live pose.
    void setQuality(int width, int height, float spacing);

    void setPinMode(PinMode mode);
    PinMode pinMode() const { return pinMode_; }

    // Uniform scale on rest garment width/length (XS–XXL). Clamped [0.72, 1.40].
    void setSizeScale(float scale);
    float sizeScale() const { return sizeScale_; }

    // Fit sliders. length = V scale, tightness = U scale AND stretch mix, drape = bend mix.
    // Applied live (no topology rebuild). Length/tightness take effect on the next
    // initializeGarment; tightness also scales structural stiffness immediately;
    // drape scales bend stiffness immediately.
    void setFit(float length, float tightness, float drape);

    // Height calibration. Scales rest garment size (capsule radii are scaled on the
    // Swift side before packing). Clamped [0.80, 1.25] around a 170 cm reference.
    void setBodyScale(float scale);

    // Test/debug: overwrite one particle. Does not change invMass.
    void setParticlePosition(int index, const Vec3& x);
    int indexOf(int col, int row) const { return row * width_ + col; }

    // Place a rectangular garment patch spanning shoulders → hips, offset slightly along
    // the chest-forward axis so it starts in front of the torso and drapes under gravity
    // + collision rather than spawning inside the body. Top-row particles become kinematic
    // anchors that follow the shoulder line (updated via updateShoulderAnchors), except
    // pants which pin the hip line.
    //
    // All four points are ARKit world-space meters.
    void initializeGarment(const Vec3& leftShoulder,
                           const Vec3& rightShoulder,
                           const Vec3& leftHip,
                           const Vec3& rightHip,
                           const Vec3& preferToward);

    // Reposition the kinematic top row between the current shoulder (or hip, for pants)
    // world positions. Call every frame before step() so the garment stays attached.
    void updateShoulderAnchors(const Vec3& leftShoulder,
                               const Vec3& rightShoulder,
                               const Vec3& preferToward);

    // Advance the simulation. dt is the *frame* delta in seconds; internally split into
    // `substeps` slices of dt/substeps, each clamped to (0, 1/30] to keep Verlet stable
    // when the render thread hitchs.
    void step(float dt);

    // Tightly packed xyz (3 * particleCount floats). Pointers remain valid until the next
    // initializeGarment() or setQuality(). Never returns null after construction.
    const float* positions() const { return positions_.data(); }
    const float* normals() const { return normals_.data(); }
    int particleCount() const { return width_ * height_; }
    int width() const { return width_; }
    int height() const { return height_; }
    float spacing() const { return spacing_; }

    const std::uint32_t* indices() const { return indices_.data(); }
    int indexCount() const { return static_cast<int>(indices_.size()); }

private:
    struct Particle {
        Vec3 x;
        Vec3 prev;
        float invMass = 1.f; // 0 = kinematic (infinite mass).
        int col = 0;
        int row = 0;
    };

    enum ConstraintKind : int { kStretch = 0, kShear = 1, kBend = 2 };

    struct DistanceConstraint {
        int i = 0;
        int j = 0;
        float rest = 0.f;
        float stiffness = 1.f; // [0,1] classic PBD weight tag
        float lambda = 0.f;    // XPBD multiplier (stretch only)
        int kind = kStretch;
    };

    void rebuildBuffers(int width, int height, float spacing);
    void buildTopology(float spacing);
    void projectDistanceConstraints(float subDt);
    void collideCapsules();
    void collideEllipsoids();
    void collideSelf();
    void applyArmPins();
    void recomputeNormals();
    void applyKinematicPins();
    void placeKinematicRow(const Vec3& left, const Vec3& right, const Vec3& preferToward, float offset);

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
    std::vector<Ellipsoid> ellipsoids_;
    std::vector<Capsule> armCapsules_;

    // Spatial hash scratch (self-collision). Reused every step, no heap churn after grow.
    std::vector<int> hashHead_;
    std::vector<int> hashNext_;

    // Cached garment frame so the top row can be re-anchored without a full reset.
    Vec3 garmentForward_{0.f, 0.f, 1.f};
    Vec3 preferToward_{0.f, 1.5f, 0.f};
    Vec3 lastLeft_{0.f, 1.45f, -2.f};
    Vec3 lastRight_{0.f, 1.45f, -2.f};
    float garmentHalfWidth_ = 0.2f;
    float photoAspect_ = 0.f;
    bool garmentReady_ = false;

    Vec3 wind_{0.f, 0.f, 0.f};
    bool selfCollision_ = true;
    PinMode pinMode_ = PinMode::Tee;
    float sizeScale_ = 1.f;
    float lengthScale_ = 1.f;
    float tightness_ = 1.f;
    float drape_ = 1.f;
    float bodyScale_ = 1.f;
    float simTime_ = 0.f;
};

} // namespace fitty
