// Plain C++ harness for fitty::ClothSolver. No XCTest, no Apple frameworks.
// Build:
//   g++ -std=c++17 -O2 -I. ClothSolver.cpp ClothSolverTests.cpp -o cloth_tests && ./cloth_tests

#include "ClothSolver.hpp"

#include <cmath>
#include <cstdio>
#include <vector>

namespace {

int g_pass = 0;
int g_fail = 0;

void check(bool cond, const char* msg) {
    if (cond) {
        ++g_pass;
        std::printf("PASS  %s\n", msg);
    } else {
        ++g_fail;
        std::printf("FAIL  %s\n", msg);
    }
}

fitty::Vec3 particle(const fitty::ClothSolver& s, int col, int row) {
    const float* p = s.positions();
    const int i = row * s.width() + col;
    return fitty::Vec3{p[i * 3 + 0], p[i * 3 + 1], p[i * 3 + 2]};
}

bool allFinite(const float* p, int particleCount) {
    const int n = particleCount * 3;
    for (int i = 0; i < n; ++i) {
        if (!std::isfinite(p[i])) return false;
    }
    return true;
}

void bbox(const float* p, int particleCount, fitty::Vec3& mn, fitty::Vec3& mx) {
    mn = fitty::Vec3{ 1e9f,  1e9f,  1e9f};
    mx = fitty::Vec3{-1e9f, -1e9f, -1e9f};
    for (int i = 0; i < particleCount; ++i) {
        const float x = p[i * 3 + 0];
        const float y = p[i * 3 + 1];
        const float z = p[i * 3 + 2];
        mn.x = std::min(mn.x, x); mn.y = std::min(mn.y, y); mn.z = std::min(mn.z, z);
        mx.x = std::max(mx.x, x); mx.y = std::max(mx.y, y); mx.z = std::max(mx.z, z);
    }
}

float extent(const fitty::Vec3& mn, const fitty::Vec3& mx) {
    return std::max(mx.x - mn.x, std::max(mx.y - mn.y, mx.z - mn.z));
}

// Standing T-pose at origin (0,0,-2), matching BodyCapsuleRig.tPoseStanding.
// Shoulders ~0.4 m apart, hips ~0.3 m, Y up.
void tposeHandles(fitty::Vec3& ls, fitty::Vec3& rs, fitty::Vec3& lh, fitty::Vec3& rh,
                  fitty::Vec3& cam) {
    ls = fitty::Vec3{ 0.20f, 1.45f, -2.0f};
    rs = fitty::Vec3{-0.20f, 1.45f, -2.0f};
    lh = fitty::Vec3{ 0.15f, 0.95f, -2.0f};
    rh = fitty::Vec3{-0.15f, 0.95f, -2.0f};
    cam = fitty::Vec3{ 0.0f, 1.40f,  0.8f};
}

// Packed capsules (7 floats): spine, shoulders, hips, legs. Enough for a standing hull.
std::vector<float> standingCapsules() {
    struct C { float ax, ay, az, bx, by, bz, r; };
    const C caps[] = {
        { 0.00f, 1.52f, -2.0f,  0.00f, 1.68f, -2.0f, 0.11f}, // head
        { 0.00f, 0.95f, -2.0f,  0.00f, 1.52f, -2.0f, 0.14f}, // spine/torso
        { 0.20f, 1.45f, -2.0f, -0.20f, 1.45f, -2.0f, 0.07f}, // shoulders
        { 0.15f, 0.95f, -2.0f, -0.15f, 0.95f, -2.0f, 0.11f}, // hips
        { 0.15f, 0.95f, -2.0f,  0.15f, 0.50f, -2.0f, 0.08f}, // left thigh
        {-0.15f, 0.95f, -2.0f, -0.15f, 0.50f, -2.0f, 0.08f}, // right thigh
        { 0.15f, 0.50f, -2.0f,  0.15f, 0.08f, -2.0f, 0.055f},
        {-0.15f, 0.50f, -2.0f, -0.15f, 0.08f, -2.0f, 0.055f},
    };
    std::vector<float> out;
    out.reserve(sizeof(caps) / sizeof(caps[0]) * 7);
    for (const C& c : caps) {
        out.push_back(c.ax); out.push_back(c.ay); out.push_back(c.az);
        out.push_back(c.bx); out.push_back(c.by); out.push_back(c.bz);
        out.push_back(c.r);
    }
    return out;
}

void testConstructAndInit() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    check(solver.width() == 24, "construct 24 columns");
    check(solver.height() == 32, "construct 32 rows");
    check(solver.particleCount() == 24 * 32, "768 particles");
    check(solver.indexCount() == 23 * 31 * 6, "triangle index count");
    check(solver.positions() != nullptr, "positions never null");
    check(solver.normals() != nullptr, "normals never null");

    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    check(allFinite(solver.positions(), solver.particleCount()), "init positions finite");

    const fitty::Vec3 pL = particle(solver, 0, 0);
    const fitty::Vec3 pR = particle(solver, 23, 0);
    const float shoulderSpan = std::fabs(pL.x - pR.x);
    check(shoulderSpan > 0.30f && shoulderSpan < 0.80f,
          "top row spans roughly the shoulder line");
    check(std::fabs(pL.y - 1.45f) < 0.08f, "top row near shoulder height");
}

void testStep120FiniteAndDrape() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);

    const auto packed = standingCapsules();
    solver.setCapsules(packed.data(), static_cast<int>(packed.size() / 7));

    const float dt = 1.f / 60.f;
    for (int f = 0; f < 120; ++f) {
        solver.updateShoulderAnchors(ls, rs, cam);
        solver.step(dt);
    }

    check(allFinite(solver.positions(), solver.particleCount()),
          "120 frames: no NaN/Inf in positions");
    check(allFinite(solver.normals(), solver.particleCount()),
          "120 frames: no NaN/Inf in normals");

    fitty::Vec3 mn, mx;
    bbox(solver.positions(), solver.particleCount(), mn, mx);
    const float ext = extent(mn, mx);
    std::printf("      bbox extent=%.3f m  y=[%.3f, %.3f]\n", ext, mn.y, mx.y);
    check(std::isfinite(ext) && ext < 3.f,
          "bounding box stays finite and < 3 m (rest lengths not exploding)");

    // Hip capsule sits at y=0.95, radius 0.11. Dynamic particles should not all
    // have fallen through the floor (y near 0 or below).
    int aboveHips = 0;
    int aboveKnees = 0;
    const int n = solver.particleCount();
    const float* p = solver.positions();
    for (int i = 0; i < n; ++i) {
        const float y = p[i * 3 + 1];
        if (y > 0.95f) ++aboveHips;
        if (y > 0.50f) ++aboveKnees;
    }
    std::printf("      particles above hip y=0.95: %d / %d; above knee y=0.50: %d\n",
                aboveHips, n, aboveKnees);
    check(aboveHips >= 24, "top row + some torso particles stay above hip capsules");
    check(aboveKnees > n / 3, "most of the sheet has not fallen through the floor");
    check(mn.y > -0.5f, "hem did not fall through the floor to -inf");
}

void testCollisionPushesOut() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);

    // Plant a capsule on a dynamic interior particle so it starts inside.
    const int col = 12;
    const int row = 16; // well below the kinematic top row
    const fitty::Vec3 inside = particle(solver, col, row);
    const float radius = 0.12f;
    float packed[7] = {
        inside.x, inside.y, inside.z,
        inside.x, inside.y + 0.01f, inside.z,
        radius
    };
    // Confirm the particle is inside before stepping.
    const float distBefore = fitty::length(particle(solver, col, row) - inside);
    check(distBefore < radius, "precondition: planted particle starts inside capsule");

    solver.setCapsules(packed, 1);
    for (int i = 0; i < 8; ++i) {
        solver.step(1.f / 60.f);
    }

    const fitty::Vec3 after = particle(solver, col, row);
    // Closest point on the tiny vertical segment.
    fitty::Vec3 a{packed[0], packed[1], packed[2]};
    fitty::Vec3 b{packed[3], packed[4], packed[5]};
    const fitty::Vec3 ab = b - a;
    const float ab2 = fitty::length2(ab);
    float t = 0.f;
    if (ab2 > 1e-12f) {
        t = fitty::dot(after - a, ab) / ab2;
        t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
    }
    const fitty::Vec3 closest = a + ab * t;
    const float dist = fitty::length(after - closest);
    std::printf("      collision dist after step=%.4f (radius=%.3f)\n", dist, radius);
    check(dist + 1e-3f >= radius, "particle planted inside a capsule is outside after collide");
    check(std::isfinite(after.x) && std::isfinite(after.y) && std::isfinite(after.z),
          "collision resolve produced a finite position");
}

void testPhotoAspectWidens() {
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);

    fitty::ClothSolver square(24, 32, 0.018f);
    square.setPhotoAspect(0.f);
    square.initializeGarment(ls, rs, lh, rh, cam);
    const float span0 = std::fabs(particle(square, 0, 0).x - particle(square, 23, 0).x);

    fitty::ClothSolver wide(24, 32, 0.018f);
    wide.setPhotoAspect(1.6f); // wide shirt
    wide.initializeGarment(ls, rs, lh, rh, cam);
    const float spanW = std::fabs(particle(wide, 0, 0).x - particle(wide, 23, 0).x);

    std::printf("      body span=%.3f m  wide-photo span=%.3f m\n", span0, spanW);
    check(spanW > span0 * 1.05f, "wide photo aspect grows garment across the shoulders");
    check(spanW < 1.2f, "wide photo aspect is clamped (not exploding)");
}

} // namespace

int main() {
    std::printf("Fitty ClothSolver tests (24x32, restSpacing=0.018 m)\n");
    testConstructAndInit();
    testStep120FiniteAndDrape();
    testCollisionPushesOut();
    testPhotoAspectWidens();
    std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
