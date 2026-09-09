import Foundation
import QuartzCore
import RealityKit
import simd

/// Owns the C++ PBD/XPBD solver, the background simulation queue, and the RealityKit
/// cloth entity. Ticked from the AR scene update; the solver itself never runs on
/// the main UI thread (`com.junholee.Fitty.pbd`).
final class ClothSimulationComponent {

    private(set) var gridWidth: Int
    private(set) var gridHeight: Int
    private(set) var restSpacing: Float

    private(set) var bridge: ClothSolverBridge
    private(set) var meshEntity: ClothMeshEntity
    let simulationQueue = DispatchQueue(label: "com.junholee.Fitty.pbd", qos: .userInteractive)

    weak var status: SimulationStatus?
    weak var meshParent: Entity?

    private let lock = NSLock()
    private var packedCapsules: [Float]
    private var packedCapsulesSim: [Float]
    private var capsuleCount = 0
    private var packedEllipsoids: [Float]
    private var packedEllipsoidsSim: [Float]
    private var ellipsoidCount = 0
    private var packedArms: [Float]
    private var packedArmsSim: [Float]
    private var armCount = 0
    private var leftShoulder = SIMD3<Float>(repeating: 0)
    private var rightShoulder = SIMD3<Float>(repeating: 0)
    private var leftHip = SIMD3<Float>(repeating: 0)
    private var rightHip = SIMD3<Float>(repeating: 0)
    private var preferToward = SIMD3<Float>(0, 1.5, 0)
    private var needsGarmentReset = true
    private var hasPose = false
    private var photoAspect: Float = 0
    private var pinMode: Int32 = 0
    private var sizeScale: Float = 1
    private var bodyScale: Float = 1
    private var fitLength: Float = 1
    private var fitTightness: Float = 1
    private var fitDrape: Float = 1
    private var wind = SIMD3<Float>(repeating: 0)
    private var fabric = FabricPreset.cotton
    private var pendingQuality: SimQuality?
    private var appliedQuality: SimQuality = .med

    private var positionScratch: [Float]
    private var normalScratch: [Float]
    private var stepping = false

    private var hzAccum: Double = 0
    private var hzFrames: Int = 0
    private var displayedHz: Double = 0

    init(quality: SimQuality = .med) {
        self.gridWidth = quality.width
        self.gridHeight = quality.height
        self.restSpacing = quality.spacing
        self.appliedQuality = quality
        bridge = ClothSolverBridge(width: Int32(quality.width),
                                   height: Int32(quality.height),
                                   spacing: quality.spacing)
        let indexCount = Int(bridge.indexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        if indexCount > 0 {
            let src = bridge.indices
            indices.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: src, count: indexCount)
            }
        }
        meshEntity = ClothMeshEntity(width: quality.width, height: quality.height, indices: indices)

        let capsuleFloats = 32 * BodyCapsule.packedStride
        packedCapsules = [Float](repeating: 0, count: capsuleFloats)
        packedCapsulesSim = [Float](repeating: 0, count: capsuleFloats)
        packedEllipsoids = [Float](repeating: 0, count: 8 * BodyEllipsoid.packedStride)
        packedEllipsoidsSim = [Float](repeating: 0, count: 8 * BodyEllipsoid.packedStride)
        packedArms = [Float](repeating: 0, count: 8 * BodyCapsule.packedStride)
        packedArmsSim = [Float](repeating: 0, count: 8 * BodyCapsule.packedStride)
        let packedCount = max(32 * 40, Int(bridge.particleCount)) * 3
        positionScratch = [Float](repeating: 0, count: packedCount)
        normalScratch = [Float](repeating: 0, count: packedCount)
        applyFabricLocked(fabric)
    }

    func setPhotoAspect(_ aspect: Float) {
        lock.lock(); photoAspect = aspect; lock.unlock()
    }

    func requestGarmentReset() {
        lock.lock(); needsGarmentReset = true; lock.unlock()
    }

    func setRuntime(fabric: FabricPreset,
                    size: GarmentSize,
                    kind: GarmentKind,
                    fitLength: Float,
                    fitTightness: Float,
                    fitDrape: Float,
                    wind: SIMD3<Float>,
                    bodyScale: Float) {
        lock.lock()
        self.fabric = fabric
        self.sizeScale = size.scale
        self.pinMode = kind.pinMode
        self.fitLength = fitLength
        self.fitTightness = fitTightness
        self.fitDrape = fitDrape
        self.wind = wind
        self.bodyScale = bodyScale
        lock.unlock()
    }

    func setQuality(_ quality: SimQuality) {
        lock.lock()
        pendingQuality = quality
        lock.unlock()
    }

    func ingest(capsules: [BodyCapsule],
                ellipsoids: [BodyEllipsoid],
                arms: [BodyCapsule],
                torso: BodyCapsuleRig.TorsoHandles,
                cameraWorld: SIMD3<Float>,
                resetGarment: Bool) {
        lock.lock()
        capsuleCount = min(capsules.count, packedCapsules.count / BodyCapsule.packedStride)
        for i in 0..<capsuleCount { capsules[i].pack(into: &packedCapsules, at: i) }
        ellipsoidCount = min(ellipsoids.count, packedEllipsoids.count / BodyEllipsoid.packedStride)
        for i in 0..<ellipsoidCount { ellipsoids[i].pack(into: &packedEllipsoids, at: i) }
        armCount = min(arms.count, packedArms.count / BodyCapsule.packedStride)
        for i in 0..<armCount { arms[i].pack(into: &packedArms, at: i) }
        leftShoulder = torso.leftShoulder
        rightShoulder = torso.rightShoulder
        leftHip = torso.leftHip
        rightHip = torso.rightHip
        preferToward = cameraWorld
        if resetGarment { needsGarmentReset = true }
        hasPose = true
        lock.unlock()
    }

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
        var eCount = 0
        var aCount = 0
        var ls = SIMD3<Float>()
        var rs = SIMD3<Float>()
        var lh = SIMD3<Float>()
        var rh = SIMD3<Float>()
        var toward = SIMD3<Float>()
        var reset = false
        var ready = false
        var aspect: Float = 0
        var pin: Int32 = 0
        var size: Float = 1
        var body: Float = 1
        var length: Float = 1
        var tight: Float = 1
        var drape: Float = 1
        var windV = SIMD3<Float>()
        var fabricV = FabricPreset.cotton
        var quality: SimQuality?

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
                if let d = dst.baseAddress, let s = src.baseAddress, n > 0 { d.update(from: s, count: n) }
            }
        }
        eCount = ellipsoidCount
        packedEllipsoidsSim.withUnsafeMutableBufferPointer { dst in
            packedEllipsoids.withUnsafeBufferPointer { src in
                let n = min(dst.count, src.count)
                if let d = dst.baseAddress, let s = src.baseAddress, n > 0 { d.update(from: s, count: n) }
            }
        }
        aCount = armCount
        packedArmsSim.withUnsafeMutableBufferPointer { dst in
            packedArms.withUnsafeBufferPointer { src in
                let n = min(dst.count, src.count)
                if let d = dst.baseAddress, let s = src.baseAddress, n > 0 { d.update(from: s, count: n) }
            }
        }
        ls = leftShoulder; rs = rightShoulder
        lh = leftHip; rh = rightHip
        toward = preferToward
        reset = needsGarmentReset
        aspect = photoAspect
        pin = pinMode
        size = sizeScale
        body = bodyScale
        length = fitLength
        tight = fitTightness
        drape = fitDrape
        windV = wind
        fabricV = fabric
        quality = pendingQuality
        pendingQuality = nil
        needsGarmentReset = false
        lock.unlock()

        if let quality, quality != appliedQuality {
            rebuildQualityOnSimThread(quality)
            reset = true
        }

        applyFabricLocked(fabricV)
        bridge.setXPBDCompliance(fabricV.physics.xpbd)
        bridge.enableSelfCollision(true)
        bridge.setPinMode(pin)
        bridge.setSizeScale(size)
        bridge.setBodyScale(body)
        bridge.setFit(length: length, tightness: tight, drape: drape)
        bridge.setWind(x: windV.x, y: windV.y, z: windV.z)
        bridge.setPhotoAspect(aspect)

        if count > 0 {
            packedCapsulesSim.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress { bridge.updateCapsules(data: base, count: Int32(count)) }
            }
        }
        if eCount > 0 {
            packedEllipsoidsSim.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress { bridge.setVolumeEllipsoids(data: base, count: Int32(eCount)) }
            }
        }
        if aCount > 0 {
            packedArmsSim.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress { bridge.setArmCapsules(data: base, count: Int32(aCount)) }
            }
        }

        func asXYZ(_ v: SIMD3<Float>, _ body: (UnsafePointer<Float>) -> Void) {
            var copy = v
            withUnsafeBytes(of: &copy) { raw in
                body(raw.bindMemory(to: Float.self).baseAddress!)
            }
        }

        // Pants pin the hip line; everything else pins the shoulders.
        let pinLeft = (pin == 4) ? lh : ls
        let pinRight = (pin == 4) ? rh : rs

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
            asXYZ(pinLeft) { lp in
                asXYZ(pinRight) { rp in
                    asXYZ(toward) { cam in
                        bridge.updateShoulderAnchors(left: lp, right: rp, preferToward: cam)
                    }
                }
            }
        }

        bridge.step(deltaTime: dt)

        let floats = Int(bridge.particleCount) * 3
        if floats > 0 {
            if floats > positionScratch.count {
                positionScratch = [Float](repeating: 0, count: floats)
                normalScratch = [Float](repeating: 0, count: floats)
            }
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
        let qLabel = "\(bridge.width)×\(bridge.height)"
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
            self.status?.qualityLabel = qLabel
        }
    }

    private func applyFabricLocked(_ fabric: FabricPreset) {
        let p = fabric.physics
        bridge.setConfig(mass: p.mass, damping: p.damping, stretch: p.stretch, shear: p.shear, bend: p.bend, friction: p.friction)
    }

    private func rebuildQualityOnSimThread(_ quality: SimQuality) {
        appliedQuality = quality
        gridWidth = quality.width
        gridHeight = quality.height
        restSpacing = quality.spacing
        bridge.setQuality(width: Int32(quality.width), height: Int32(quality.height), spacing: quality.spacing)
        let indexCount = Int(bridge.indexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        if indexCount > 0 {
            let src = bridge.indices
            indices.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress?.update(from: src, count: indexCount)
            }
        }
        let w = quality.width
        let h = quality.height
        DispatchQueue.main.sync {
            let parent = self.meshEntity.parent ?? self.meshParent
            self.meshEntity.removeFromParent()
            self.meshEntity = ClothMeshEntity(width: w, height: h, indices: indices)
            parent?.addChild(self.meshEntity)
        }
    }
}
