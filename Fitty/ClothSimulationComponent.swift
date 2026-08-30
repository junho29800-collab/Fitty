import Foundation
import QuartzCore
import simd

/// Owns the C++ PBD solver, the background simulation queue, and the RealityKit
/// cloth entity. Ticked from the AR scene update; the solver itself never runs on
/// the main UI thread.
///
/// Pipeline per frame:
/// 1. The AR session / host copies world-space capsules + shoulder/hip handles
///    into preallocated scratch (this may happen on the session queue).
/// 2. `tick(deltaTime:)` hops onto `simulationQueue` (serial). If a step is already
///    in flight we drop the frame rather than queue a backlog.
/// 3. After `step`, positions/normals are memcpy'd into Swift-side scratch and
///    uploaded on the main queue, which is also RealityKit's render thread.
final class ClothSimulationComponent {

    static let gridWidth = 24
    static let gridHeight = 32
    /// Rest spacing of adjacent particles in meters. A 24×32 grid at 1.8 cm spans
    /// roughly 41 cm × 56 cm at rest — a fitted torso patch. The live garment is
    /// *placed* from the skeleton (shoulders/hips) so a larger body starts slightly
    /// pre-stretched.
    static let restSpacing: Float = 0.018

    let bridge: ClothSolverBridge
    let meshEntity: ClothMeshEntity
    let simulationQueue = DispatchQueue(label: "com.junholee.Fitty.pbd", qos: .userInteractive)

    weak var status: SimulationStatus?

    private let lock = NSLock()
    private var packedCapsules: [Float]
    private var packedCapsulesSim: [Float]
    private var capsuleCount = 0
    private var leftShoulder = SIMD3<Float>(repeating: 0)
    private var rightShoulder = SIMD3<Float>(repeating: 0)
    private var leftHip = SIMD3<Float>(repeating: 0)
    private var rightHip = SIMD3<Float>(repeating: 0)
    private var preferToward = SIMD3<Float>(0, 1.5, 0)
    private var needsGarmentReset = true
    private var hasPose = false

    private var positionScratch: [Float]
    private var normalScratch: [Float]
    private var stepping = false

    private var hzAccum: Double = 0
    private var hzFrames: Int = 0
    private var displayedHz: Double = 0

    init() {
        let w = Self.gridWidth
        let h = Self.gridHeight
        bridge = ClothSolverBridge(width: Int32(w), height: Int32(h), spacing: Self.restSpacing)
        let indexCount = Int(bridge.indexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        if indexCount > 0 {
            let src = bridge.indices
            indices.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: src, count: indexCount)
            }
        }
        meshEntity = ClothMeshEntity(width: w, height: h, indices: indices)

        let capsuleFloats = 32 * BodyCapsule.packedStride
        packedCapsules = [Float](repeating: 0, count: capsuleFloats)
        packedCapsulesSim = [Float](repeating: 0, count: capsuleFloats)
        let packedCount = Int(bridge.particleCount) * 3
        positionScratch = [Float](repeating: 0, count: packedCount)
        normalScratch = [Float](repeating: 0, count: packedCount)
    }

    /// Store the latest body proxy. Safe to call from the AR session queue.
    func ingest(capsules: [BodyCapsule],
                torso: BodyCapsuleRig.TorsoHandles,
                cameraWorld: SIMD3<Float>,
                resetGarment: Bool) {
        lock.lock()
        capsuleCount = min(capsules.count, packedCapsules.count / BodyCapsule.packedStride)
        for i in 0..<capsuleCount {
            capsules[i].pack(into: &packedCapsules, at: i)
        }
        leftShoulder = torso.leftShoulder
        rightShoulder = torso.rightShoulder
        leftHip = torso.leftHip
        rightHip = torso.rightHip
        preferToward = cameraWorld
        if resetGarment { needsGarmentReset = true }
        hasPose = true
        lock.unlock()
    }

    /// Dispatch one PBD step. Call from the RealityKit scene-update callback with
    /// that callback's `deltaTime`. Drops the frame if the previous step is still running.
    func tick(deltaTime: TimeInterval) {
        let dt = Float(min(max(deltaTime, 1.0 / 240.0), 1.0 / 20.0))
        simulationQueue.async { [weak self] in
            self?.stepOnSimulationThread(dt: dt)
        }
    }

    private func stepOnSimulationThread(dt: Float) {
        if stepping { return }
        stepping = true
        let t0 = CACurrentMediaTime()

        var count = 0
        var ls = SIMD3<Float>()
        var rs = SIMD3<Float>()
        var lh = SIMD3<Float>()
        var rh = SIMD3<Float>()
        var toward = SIMD3<Float>()
        var reset = false
        var ready = false

        lock.lock()
        ready = hasPose
        if !ready {
            lock.unlock()
            stepping = false
            return
        }
        count = capsuleCount
        packedCapsulesSim.withUnsafeMutableBufferPointer { dst in
            packedCapsules.withUnsafeBufferPointer { src in
                let n = min(dst.count, src.count)
                if let d = dst.baseAddress, let s = src.baseAddress, n > 0 {
                    d.update(from: s, count: n)
                }
            }
        }
        ls = leftShoulder; rs = rightShoulder
        lh = leftHip; rh = rightHip
        toward = preferToward
        reset = needsGarmentReset
        needsGarmentReset = false
        lock.unlock()

        if count > 0 {
            packedCapsulesSim.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    bridge.updateCapsules(data: base, count: Int32(count))
                }
            }
        }

        // SIMD3 is 16-byte aligned; first three lanes are xyz. Rebound without allocating.
        func asXYZ(_ v: SIMD3<Float>, _ body: (UnsafePointer<Float>) -> Void) {
            var copy = v
            withUnsafeBytes(of: &copy) { raw in
                body(raw.bindMemory(to: Float.self).baseAddress!)
            }
        }
        if reset {
            asXYZ(ls) { lp in
                asXYZ(rs) { rp in
                    asXYZ(lh) { hipL in
                        asXYZ(rh) { hipR in
                            asXYZ(toward) { cam in
                                bridge.initializeGarment(leftShoulder: lp,
                                                         rightShoulder: rp,
                                                         leftHip: hipL,
                                                         rightHip: hipR,
                                                         preferToward: cam)
                            }
                        }
                    }
                }
            }
        } else {
            asXYZ(ls) { lp in
                asXYZ(rs) { rp in
                    asXYZ(toward) { cam in
                        bridge.updateShoulderAnchors(left: lp, right: rp, preferToward: cam)
                    }
                }
            }
        }

        bridge.step(deltaTime: dt)

        let floats = Int(bridge.particleCount) * 3
        if floats > 0, floats <= positionScratch.count {
            let srcP = bridge.positions
            positionScratch.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: srcP, count: floats)
            }
            let srcN = bridge.normals
            normalScratch.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: srcN, count: floats)
            }
        }

        let elapsed = max(CACurrentMediaTime() - t0, 1e-6)
        hzAccum += 1.0 / elapsed
        hzFrames += 1
        if hzFrames >= 15 {
            displayedHz = hzAccum / Double(hzFrames)
            hzAccum = 0
            hzFrames = 0
        }
        let hz = displayedHz
        let particles = Int(bridge.particleCount)
        stepping = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.positionScratch.withUnsafeBufferPointer { pBuf in
                self.normalScratch.withUnsafeBufferPointer { nBuf in
                    guard let p = pBuf.baseAddress, let n = nBuf.baseAddress else { return }
                    self.meshEntity.upload(positionsPacked: p, normalsPacked: n, particleCount: particles)
                }
            }
            self.status?.simHz = hz
            self.status?.particleCount = particles
        }
    }
}
