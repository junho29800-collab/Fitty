import ARKit
import simd

/// A collision capsule in ARKit world space (meters): a line segment plus a radius.
/// Packed for the C++ solver as 7 tightly packed floats: ax,ay,az, bx,by,bz, radius.
struct BodyCapsule: Equatable {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var radius: Float

    static let packedStride = 7

    func pack(into out: inout [Float], at capsuleIndex: Int) {
        let o = capsuleIndex * BodyCapsule.packedStride
        out[o + 0] = a.x; out[o + 1] = a.y; out[o + 2] = a.z
        out[o + 3] = b.x; out[o + 4] = b.y; out[o + 5] = b.z
        out[o + 6] = radius
    }
}

/// Oriented volume for chest / hip so the sheet sits on the torso, not in it.
/// Packed as 12 floats: cx,cy,cz, rx,ry,rz, ux,uy,uz, vx,vy,vz.
struct BodyEllipsoid: Equatable {
    var center: SIMD3<Float>
    var radii: SIMD3<Float>
    var axisU: SIMD3<Float>
    var axisV: SIMD3<Float>

    static let packedStride = 12

    func pack(into out: inout [Float], at i: Int) {
        let o = i * BodyEllipsoid.packedStride
        out[o + 0] = center.x; out[o + 1] = center.y; out[o + 2] = center.z
        out[o + 3] = radii.x;  out[o + 4] = radii.y;  out[o + 5] = radii.z
        out[o + 6] = axisU.x;  out[o + 7] = axisU.y;  out[o + 8] = axisU.z
        out[o + 9] = axisV.x;  out[o + 10] = axisV.y; out[o + 11] = axisV.z
    }
}

/// Maps an `ARSkeleton3D` (or a standing T-pose) onto a small set of capsules that
/// approximate the body for cloth collision. Capsules are an inner hull: cheap and
/// stable, but they will not capture chest/breast/glute detail — an SDF is the
/// follow-up if cloth still clips on a fitted garment.
///
/// Space: every joint is converted to **ARKit world space** via
/// `bodyAnchor.transform * skeleton.modelTransform(for:)`. `modelTransform` is
/// relative to the body-anchor root; `localTransform` is parent-relative and must
/// not be mixed in. The C++ solver uses the same world meters.
enum BodyCapsuleRig {

    /// Anatomical joint names that don't all have `ARSkeleton.JointName` constants.
    enum Joint {
        static let hips = ARSkeleton.JointName(rawValue: "hips_joint")
        static let spine3 = ARSkeleton.JointName(rawValue: "spine_3_joint")
        static let spine7 = ARSkeleton.JointName(rawValue: "spine_7_joint")
        static let neck1 = ARSkeleton.JointName(rawValue: "neck_1_joint")
        static let head = ARSkeleton.JointName.head
        static let leftShoulder = ARSkeleton.JointName.leftShoulder
        static let rightShoulder = ARSkeleton.JointName.rightShoulder
        static let leftArm = ARSkeleton.JointName(rawValue: "left_arm_joint")       // elbow
        static let rightArm = ARSkeleton.JointName(rawValue: "right_arm_joint")
        static let leftForearm = ARSkeleton.JointName(rawValue: "left_forearm_joint") // wrist
        static let rightForearm = ARSkeleton.JointName(rawValue: "right_forearm_joint")
        static let leftUpLeg = ARSkeleton.JointName(rawValue: "left_upLeg_joint")    // hip
        static let rightUpLeg = ARSkeleton.JointName(rawValue: "right_upLeg_joint")
        static let leftLeg = ARSkeleton.JointName(rawValue: "left_leg_joint")        // knee
        static let rightLeg = ARSkeleton.JointName(rawValue: "right_leg_joint")
        static let leftFoot = ARSkeleton.JointName.leftFoot
        static let rightFoot = ARSkeleton.JointName.rightFoot
    }

    struct TorsoHandles {
        var leftShoulder: SIMD3<Float>
        var rightShoulder: SIMD3<Float>
        var leftHip: SIMD3<Float>
        var rightHip: SIMD3<Float>
    }

    static func worldPosition(of joint: ARSkeleton.JointName, body: ARBodyAnchor) -> SIMD3<Float>? {
        guard let model = body.skeleton.modelTransform(for: joint) else { return nil }
        let world = body.transform * model
        return SIMD3<Float>(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }

    static func capsules(from body: ARBodyAnchor, scale: Float = 1) -> [BodyCapsule] {
        func p(_ joint: ARSkeleton.JointName) -> SIMD3<Float>? {
            worldPosition(of: joint, body: body)
        }

        var out: [BodyCapsule] = []
        out.reserveCapacity(13)

        if let a = p(Joint.neck1) ?? p(Joint.spine7), let b = p(Joint.head) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.11 * scale))
        }
        if let a = p(Joint.hips), let b = p(Joint.spine7) ?? p(Joint.neck1) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.14 * scale))
        }
        if let a = p(Joint.leftShoulder), let b = p(Joint.rightShoulder) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.07 * scale))
        }
        if let a = p(Joint.leftUpLeg), let b = p(Joint.rightUpLeg) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.11 * scale))
        }
        if let a = p(Joint.leftShoulder), let b = p(Joint.leftArm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        if let a = p(Joint.leftArm), let b = p(Joint.leftForearm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.045 * scale))
        }
        if let a = p(Joint.rightShoulder), let b = p(Joint.rightArm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        if let a = p(Joint.rightArm), let b = p(Joint.rightForearm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.045 * scale))
        }
        if let a = p(Joint.leftUpLeg), let b = p(Joint.leftLeg) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.08 * scale))
        }
        if let a = p(Joint.leftLeg), let b = p(Joint.leftFoot) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        if let a = p(Joint.rightUpLeg), let b = p(Joint.rightLeg) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.08 * scale))
        }
        if let a = p(Joint.rightLeg), let b = p(Joint.rightFoot) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        return out
    }

    static func torsoHandles(from body: ARBodyAnchor) -> TorsoHandles? {
        guard
            let ls = worldPosition(of: Joint.leftShoulder, body: body),
            let rs = worldPosition(of: Joint.rightShoulder, body: body),
            let lh = worldPosition(of: Joint.leftUpLeg, body: body)
                    ?? worldPosition(of: Joint.hips, body: body),
            let rh = worldPosition(of: Joint.rightUpLeg, body: body)
                    ?? worldPosition(of: Joint.hips, body: body)
        else { return nil }
        return TorsoHandles(leftShoulder: ls, rightShoulder: rs, leftHip: lh, rightHip: rh)
    }

    static func tPoseStanding(at origin: SIMD3<Float> = SIMD3(0, 0, -2), scale: Float = 1) -> (capsules: [BodyCapsule], torso: TorsoHandles) {
        func w(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            origin + SIMD3(x, y, z)
        }
        let leftShoulder = w(0.18, 1.45, 0)
        let rightShoulder = w(-0.18, 1.45, 0)
        let leftHip = w(0.12, 0.95, 0)
        let rightHip = w(-0.12, 0.95, 0)
        let hips = w(0, 0.95, 0)
        let neck = w(0, 1.52, 0)
        let head = w(0, 1.68, 0)
        let leftElbow = w(0.48, 1.45, 0)
        let rightElbow = w(-0.48, 1.45, 0)
        let leftWrist = w(0.72, 1.45, 0)
        let rightWrist = w(-0.72, 1.45, 0)
        let leftKnee = w(0.12, 0.50, 0)
        let rightKnee = w(-0.12, 0.50, 0)
        let leftAnkle = w(0.12, 0.08, 0)
        let rightAnkle = w(-0.12, 0.08, 0)

        let capsules: [BodyCapsule] = [
            BodyCapsule(a: neck, b: head, radius: 0.11 * scale),
            BodyCapsule(a: hips, b: neck, radius: 0.14 * scale),
            BodyCapsule(a: leftShoulder, b: rightShoulder, radius: 0.07 * scale),
            BodyCapsule(a: leftHip, b: rightHip, radius: 0.11 * scale),
            BodyCapsule(a: leftShoulder, b: leftElbow, radius: 0.055 * scale),
            BodyCapsule(a: leftElbow, b: leftWrist, radius: 0.045 * scale),
            BodyCapsule(a: rightShoulder, b: rightElbow, radius: 0.055 * scale),
            BodyCapsule(a: rightElbow, b: rightWrist, radius: 0.045 * scale),
            BodyCapsule(a: leftHip, b: leftKnee, radius: 0.08 * scale),
            BodyCapsule(a: leftKnee, b: leftAnkle, radius: 0.055 * scale),
            BodyCapsule(a: rightHip, b: rightKnee, radius: 0.08 * scale),
            BodyCapsule(a: rightKnee, b: rightAnkle, radius: 0.055 * scale)
        ]
        let torso = TorsoHandles(leftShoulder: leftShoulder,
                                 rightShoulder: rightShoulder,
                                 leftHip: leftHip,
                                 rightHip: rightHip)
        return (capsules, torso)
    }

    static func volumeEllipsoids(torso: TorsoHandles, cameraWorld: SIMD3<Float>, scale: Float = 1) -> [BodyEllipsoid] {
        let shoulderMid = (torso.leftShoulder + torso.rightShoulder) * 0.5
        let hipMid = (torso.leftHip + torso.rightHip) * 0.5
        var across = torso.rightShoulder - torso.leftShoulder
        if simd_length(across) < 1e-4 { across = SIMD3(1, 0, 0) }
        let u = simd_normalize(across)
        var down = hipMid - shoulderMid
        if simd_length(down) < 1e-4 { down = SIMD3(0, -1, 0) }
        let v = simd_normalize(down)
        var forward = simd_cross(u, SIMD3(0, 1, 0))
        if simd_length(forward) < 1e-4 { forward = SIMD3(0, 0, 1) }
        forward = simd_normalize(forward)
        if simd_dot(forward, cameraWorld - shoulderMid) < 0 { forward = -forward }
        let chest = (shoulderMid * 0.55 + hipMid * 0.45) + forward * (0.04 * scale)
        let hip = hipMid + forward * (0.03 * scale)
        let chestRadii = SIMD3<Float>(0.16, 0.13, 0.11) * scale
        let hipRadii = SIMD3<Float>(0.15, 0.10, 0.12) * scale
        return [
            BodyEllipsoid(center: chest, radii: chestRadii, axisU: u, axisV: SIMD3(0, 1, 0)),
            BodyEllipsoid(center: hip, radii: hipRadii, axisU: u, axisV: SIMD3(0, 1, 0))
        ]
    }

    static func upperArmCapsules(from body: ARBodyAnchor, scale: Float = 1) -> [BodyCapsule] {
        func p(_ joint: ARSkeleton.JointName) -> SIMD3<Float>? {
            worldPosition(of: joint, body: body)
        }
        var out: [BodyCapsule] = []
        if let a = p(Joint.leftShoulder), let b = p(Joint.leftArm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        if let a = p(Joint.rightShoulder), let b = p(Joint.rightArm) {
            out.append(BodyCapsule(a: a, b: b, radius: 0.055 * scale))
        }
        return out
    }

    static func upperArmCapsulesTPose(torso: TorsoHandles, scale: Float = 1) -> [BodyCapsule] {
        let leftElbow = torso.leftShoulder + SIMD3(0.30, 0, 0)
        let rightElbow = torso.rightShoulder + SIMD3(-0.30, 0, 0)
        return [
            BodyCapsule(a: torso.leftShoulder, b: leftElbow, radius: 0.055 * scale),
            BodyCapsule(a: torso.rightShoulder, b: rightElbow, radius: 0.055 * scale)
        ]
    }

    static func scaled(_ capsules: [BodyCapsule], by scale: Float) -> [BodyCapsule] {
        capsules.map { BodyCapsule(a: $0.a, b: $0.b, radius: $0.radius * scale) }
    }
}
