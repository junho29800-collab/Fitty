// Plain C++ harness for fitty::ClothSolver. No XCTest, no Apple frameworks.
// Build:
//   g++ -std=c++17 -O2 -IFitty/Physics Fitty/Physics/ClothSolver.cpp Tests/ClothSolverTests.cpp -o /tmp/cloth_tests && /tmp/cloth_tests

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

fitty::Vec3 comOf(const fitty::ClothSolver& s) {
    const float* p = s.positions();
    const int n = s.particleCount();
    fitty::Vec3 c{0, 0, 0};
    for (int i = 0; i < n; ++i) {
        c.x += p[i * 3 + 0];
        c.y += p[i * 3 + 1];
        c.z += p[i * 3 + 2];
    }
    const float inv = n > 0 ? 1.f / static_cast<float>(n) : 0.f;
    return c * inv;
}

void tposeHandles(fitty::Vec3& ls, fitty::Vec3& rs, fitty::Vec3& lh, fitty::Vec3& rh,
                  fitty::Vec3& cam) {
    ls = fitty::Vec3{ 0.20f, 1.45f, -2.0f};
    rs = fitty::Vec3{-0.20f, 1.45f, -2.0f};
    lh = fitty::Vec3{ 0.15f, 0.95f, -2.0f};
    rh = fitty::Vec3{-0.15f, 0.95f, -2.0f};
    cam = fitty::Vec3{ 0.0f, 1.40f,  0.8f};
}

std::vector<float> standingCapsules() {
    struct C { float ax, ay, az, bx, by, bz, r; };
    const C caps[] = {
        { 0.00f, 1.52f, -2.0f,  0.00f, 1.68f, -2.0f, 0.11f},
        { 0.00f, 0.95f, -2.0f,  0.00f, 1.52f, -2.0f, 0.14f},
        { 0.20f, 1.45f, -2.0f, -0.20f, 1.45f, -2.0f, 0.07f},
        { 0.15f, 0.95f, -2.0f, -0.15f, 0.95f, -2.0f, 0.11f},
        { 0.15f, 0.95f, -2.0f,  0.15f, 0.50f, -2.0f, 0.08f},
        {-0.15f, 0.95f, -2.0f, -0.15f, 0.50f, -2.0f, 0.08f},
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

    const int col = 12;
    const int row = 16;
    const fitty::Vec3 inside = particle(solver, col, row);
    const float radius = 0.12f;
    float packed[7] = {
        inside.x, inside.y, inside.z,
        inside.x, inside.y + 0.01f, inside.z,
        radius
    };
    const float distBefore = fitty::length(particle(solver, col, row) - inside);
    check(distBefore < radius, "precondition: planted particle starts inside capsule");

    solver.setCapsules(packed, 1);
    for (int i = 0; i < 8; ++i) {
        solver.step(1.f / 60.f);
    }

    const fitty::Vec3 after = particle(solver, col, row);
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
    wide.setPhotoAspect(1.6f);
    wide.initializeGarment(ls, rs, lh, rh, cam);
    const float spanW = std::fabs(particle(wide, 0, 0).x - particle(wide, 23, 0).x);

    std::printf("      body span=%.3f m  wide-photo span=%.3f m\n", span0, spanW);
    check(spanW > span0 * 1.05f, "wide photo aspect grows garment across the shoulders");
    check(spanW < 1.2f, "wide photo aspect is clamped (not exploding)");
}

void testEllipsoidPushOut() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);

    const int idx = solver.indexOf(12, 16);
    const fitty::Vec3 inside = particle(solver, 12, 16);
    // Axis-aligned ellipsoid centred on the particle, radii 0.10 m.
    float packed[12] = {
        inside.x, inside.y, inside.z,
        0.10f, 0.08f, 0.09f,
        1.f, 0.f, 0.f,
        0.f, 1.f, 0.f
    };
    solver.setVolumeEllipsoids(packed, 1);
    solver.setParticlePosition(idx, inside);
    check(fitty::length(particle(solver, 12, 16) - inside) < 0.01f,
          "precondition: particle at ellipsoid centre");

    for (int i = 0; i < 8; ++i) solver.step(1.f / 60.f);

    const fitty::Vec3 after = particle(solver, 12, 16);
    const fitty::Vec3 d = after - inside;
    const float lx = d.x / 0.10f;
    const float ly = d.y / 0.08f;
    const float lz = d.z / 0.09f;
    const float q = lx * lx + ly * ly + lz * lz;
    std::printf("      ellipsoid q after step=%.4f (want >= 1)\n", q);
    check(q + 1e-3f >= 1.f, "particle planted inside a volume ellipsoid is on/outside after collide");
    check(std::isfinite(after.x) && std::isfinite(after.y) && std::isfinite(after.z),
          "ellipsoid resolve produced a finite position");
}

void testSelfCollisionSeparation() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    solver.enableSelfCollision(true);

    const int a = solver.indexOf(4, 8);
    const int b = solver.indexOf(20, 24); // far in grid space, not a neighbour
    const fitty::Vec3 mid = particle(solver, 12, 16);
    solver.setParticlePosition(a, mid);
    solver.setParticlePosition(b, mid + fitty::Vec3{0.002f, 0.f, 0.f});

    const float before = fitty::length(particle(solver, 4, 8) - particle(solver, 20, 24));
    check(before < 0.7f * 0.018f, "precondition: non-adjacent particles closer than 0.7*spacing");

    // Zero gravity so they don't just fall apart; self-collision should separate them.
    fitty::ClothConfig cfg = solver.config();
    cfg.gravityY = 0.f;
    solver.setConfig(cfg);
    solver.setCapsules(nullptr, 0);
    for (int i = 0; i < 6; ++i) solver.step(1.f / 60.f);

    const float after = fitty::length(particle(solver, 4, 8) - particle(solver, 20, 24));
    std::printf("      self-collision dist before=%.4f after=%.4f (min=%.4f)\n",
                before, after, 0.7f * 0.018f);
    check(after + 1e-4f >= 0.7f * 0.018f, "self-collision separates non-adjacent particles");
    check(allFinite(solver.positions(), solver.particleCount()),
          "self-collision left positions finite");
}

void testWindMovesCOM() {
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);

    fitty::ClothSolver still(24, 32, 0.018f);
    still.enableSelfCollision(false);
    still.initializeGarment(ls, rs, lh, rh, cam);
    fitty::ClothConfig c0 = still.config();
    c0.gravityY = 0.f;
    still.setConfig(c0);
    still.setWind(fitty::Vec3{0, 0, 0});

    fitty::ClothSolver blown(24, 32, 0.018f);
    blown.enableSelfCollision(false);
    blown.initializeGarment(ls, rs, lh, rh, cam);
    fitty::ClothConfig c1 = blown.config();
    c1.gravityY = 0.f;
    blown.setConfig(c1);
    blown.setWind(fitty::Vec3{8.f, 0.f, 0.f});

    for (int i = 0; i < 40; ++i) {
        still.updateShoulderAnchors(ls, rs, cam);
        blown.updateShoulderAnchors(ls, rs, cam);
        still.step(1.f / 60.f);
        blown.step(1.f / 60.f);
    }
    const float dx = comOf(blown).x - comOf(still).x;
    std::printf("      wind COM dx=%.4f m\n", dx);
    check(dx > 0.01f, "world-space +X wind moves the centre of mass in +X");
    check(allFinite(blown.positions(), blown.particleCount()), "wind step stayed finite");
}

void testXPBDStableAtDt30() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    solver.setXPBDCompliance(2.0e-4f); // silk-ish, softer
    const auto packed = standingCapsules();
    solver.setCapsules(packed.data(), static_cast<int>(packed.size() / 7));

    for (int i = 0; i < 60; ++i) {
        solver.updateShoulderAnchors(ls, rs, cam);
        solver.step(1.f / 30.f);
    }
    check(allFinite(solver.positions(), solver.particleCount()),
          "XPBD at dt=1/30: no NaN/Inf");
    fitty::Vec3 mn, mx;
    bbox(solver.positions(), solver.particleCount(), mn, mx);
    const float ext = extent(mn, mx);
    std::printf("      XPBD dt=1/30 bbox extent=%.3f m\n", ext);
    check(std::isfinite(ext) && ext < 5.f, "XPBD at dt=1/30 did not explode the bbox");
    check(mn.y > -1.5f, "XPBD at dt=1/30 hem stayed above -1.5 m");
}

void testSizeAndAspectFiniteBBox() {
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    fitty::ClothSolver solver(24, 32, 0.018f);
    solver.setPhotoAspect(1.5f);
    solver.setSizeScale(1.30f);
    solver.setBodyScale(1.10f);
    solver.setFit(1.20f, 0.85f, 0.7f);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    check(allFinite(solver.positions(), solver.particleCount()),
          "size/aspect init positions finite");
    fitty::Vec3 mn, mx;
    bbox(solver.positions(), solver.particleCount(), mn, mx);
    const float ext = extent(mn, mx);
    std::printf("      scaled bbox extent=%.3f m\n", ext);
    check(std::isfinite(ext) && ext > 0.2f && ext < 3.f,
          "size/aspect scale produced a finite, reasonable bbox");

    fitty::ClothSolver xs(24, 32, 0.018f);
    xs.setSizeScale(0.72f);
    xs.initializeGarment(ls, rs, lh, rh, cam);
    const float spanXS = std::fabs(particle(xs, 0, 0).x - particle(xs, 23, 0).x);
    const float spanXXL = std::fabs(particle(solver, 0, 0).x - particle(solver, 23, 0).x);
    check(spanXXL > spanXS * 1.1f, "XXL size scale is wider than XS");
}

void testDenimVsSilkStretch() {
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);

    auto hemY = [](fitty::ClothSolver& s) {
        float y = 1e9f;
        const float* p = s.positions();
        const int w = s.width();
        const int last = s.height() - 1;
        for (int col = 0; col < w; ++col) {
            const int i = last * w + col;
            y = std::min(y, p[i * 3 + 1]);
        }
        return y;
    };

    fitty::ClothSolver denim(24, 32, 0.018f);
    denim.enableSelfCollision(false);
    {
        fitty::ClothConfig c = denim.config();
        c.structuralStiffness = 1.0f;
        c.xpbdCompliance = 1.0e-6f;
        c.damping = 0.08f;
        denim.setConfig(c);
        denim.setXPBDCompliance(1.0e-6f);
    }
    denim.initializeGarment(ls, rs, lh, rh, cam);

    fitty::ClothSolver silk(24, 32, 0.018f);
    silk.enableSelfCollision(false);
    {
        fitty::ClothConfig c = silk.config();
        c.structuralStiffness = 0.35f;
        c.xpbdCompliance = 3.0e-4f;
        c.damping = 0.02f;
        silk.setConfig(c);
        silk.setXPBDCompliance(3.0e-4f);
    }
    silk.initializeGarment(ls, rs, lh, rh, cam);

    const float hem0 = hemY(denim);
    for (int i = 0; i < 90; ++i) {
        denim.updateShoulderAnchors(ls, rs, cam);
        silk.updateShoulderAnchors(ls, rs, cam);
        denim.step(1.f / 60.f);
        silk.step(1.f / 60.f);
    }
    const float hemD = hemY(denim);
    const float hemS = hemY(silk);
    std::printf("      hem y denim=%.4f silk=%.4f (init=%.4f)\n", hemD, hemS, hem0);
    check(hemS < hemD - 0.005f, "silk hem sags lower than denim (different stretch)");
    check(allFinite(denim.positions(), denim.particleCount()) &&
          allFinite(silk.positions(), silk.particleCount()),
          "denim/silk step stayed finite");
}

void testPantsPinning() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.setPinMode(fitty::PinMode::Pants);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    check(allFinite(solver.positions(), solver.particleCount()), "pants init finite");

    const fitty::Vec3 pL = particle(solver, 0, 0);
    check(std::fabs(pL.y - 0.95f) < 0.12f, "pants top row sits near the hip line");

    const auto packed = standingCapsules();
    solver.setCapsules(packed.data(), static_cast<int>(packed.size() / 7));
    for (int i = 0; i < 60; ++i) {
        solver.updateShoulderAnchors(lh, rh, cam); // hip anchors
        solver.step(1.f / 60.f);
    }
    check(allFinite(solver.positions(), solver.particleCount()), "pants 60 steps: no NaN");
    check(allFinite(solver.normals(), solver.particleCount()), "pants 60 steps: normals finite");
    fitty::Vec3 mn, mx;
    bbox(solver.positions(), solver.particleCount(), mn, mx);
    check(std::isfinite(extent(mn, mx)) && extent(mn, mx) < 4.f, "pants bbox finite");
}

void testTankAndDressAndQuality() {
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);

    fitty::ClothSolver tee(24, 32, 0.018f);
    tee.setPinMode(fitty::PinMode::Tee);
    tee.initializeGarment(ls, rs, lh, rh, cam);
    const float teeSpan = std::fabs(particle(tee, 0, 0).x - particle(tee, 23, 0).x);

    fitty::ClothSolver tank(24, 32, 0.018f);
    tank.setPinMode(fitty::PinMode::Tank);
    tank.initializeGarment(ls, rs, lh, rh, cam);
    const float tankSpan = std::fabs(particle(tank, 0, 0).x - particle(tank, 23, 0).x);
    check(tankSpan < teeSpan * 0.92f, "tank is narrower in U than a tee");
    check(allFinite(tank.positions(), tank.particleCount()), "tank init finite");

    fitty::ClothSolver dress(24, 32, 0.018f);
    dress.setPinMode(fitty::PinMode::Dress);
    dress.initializeGarment(ls, rs, lh, rh, cam);
    const float teeLen = std::fabs(particle(tee, 12, 0).y - particle(tee, 12, 31).y);
    const float dressLen = std::fabs(particle(dress, 12, 0).y - particle(dress, 12, 31).y);
    check(dressLen > teeLen * 1.15f, "dress is longer in V than a tee");
    check(allFinite(dress.positions(), dress.particleCount()), "dress init finite");

    fitty::ClothSolver q(24, 32, 0.018f);
    q.setQuality(16, 20, 0.022f);
    check(q.width() == 16 && q.height() == 20, "setQuality 16x20");
    check(q.particleCount() == 320, "setQuality particle count 320");
    check(q.indexCount() == 15 * 19 * 6, "setQuality index count");
    q.setQuality(32, 40, 0.014f);
    check(q.particleCount() == 1280, "setQuality High 32x40");
    check(allFinite(q.positions(), q.particleCount()), "High quality init finite");
}

void testArmPinsFinite() {
    fitty::ClothSolver solver(24, 32, 0.018f);
    fitty::Vec3 ls, rs, lh, rh, cam;
    tposeHandles(ls, rs, lh, rh, cam);
    solver.initializeGarment(ls, rs, lh, rh, cam);
    float arms[14] = {
        0.20f, 1.45f, -2.0f,  0.48f, 1.45f, -2.0f, 0.055f,
       -0.20f, 1.45f, -2.0f, -0.48f, 1.45f, -2.0f, 0.055f
    };
    solver.setArmCapsules(arms, 2);
    for (int i = 0; i < 30; ++i) {
        solver.updateShoulderAnchors(ls, rs, cam);
        solver.step(1.f / 60.f);
    }
    check(allFinite(solver.positions(), solver.particleCount()),
          "arm-pin sleeve approximation stayed finite");
}

} // namespace

int main() {
    std::printf("Fitty ClothSolver tests (PBD + XPBD + volumes + self-collision)\n");
    testConstructAndInit();
    testStep120FiniteAndDrape();
    testCollisionPushesOut();
    testPhotoAspectWidens();
    testEllipsoidPushOut();
    testSelfCollisionSeparation();
    testWindMovesCOM();
    testXPBDStableAtDt30();
    testSizeAndAspectFiniteBBox();
    testDenimVsSilkStretch();
    testPantsPinning();
    testTankAndDressAndQuality();
    testArmPinsFinite();
    std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
