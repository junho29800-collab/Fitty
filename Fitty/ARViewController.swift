import ARKit
import RealityKit
import SwiftUI
import UIKit

/// SwiftUI wrapper around the ARKit/RealityKit host. The representable owns no
/// simulation state of its own — that lives on `ARClothHostController` so the
/// AR session survives SwiftUI redraws.
struct ARViewController: UIViewControllerRepresentable {
    @ObservedObject var status: SimulationStatus
    var garmentImage: UIImage?
    var garmentAspect: Float

    func makeUIViewController(context: Context) -> ARClothHostController {
        let host = ARClothHostController()
        host.status = status
        host.setGarment(image: garmentImage, aspect: garmentAspect)
        return host
    }

    func updateUIViewController(_ uiViewController: ARClothHostController, context: Context) {
        uiViewController.status = status
        uiViewController.setGarment(image: garmentImage, aspect: garmentAspect)
    }
}

/// Hosts an `ARView`, runs `ARBodyTrackingConfiguration` when the device can,
/// and otherwise drops into a non-AR debug scene with a standing T-pose capsule
/// rig so the PBD solver is exerciseable in Simulator.
final class ARClothHostController: UIViewController, ARSessionDelegate {

    let arView = ARView(frame: .zero)
    let simulation = ClothSimulationComponent()

    weak var status: SimulationStatus? {
        didSet { simulation.status = status }
    }

    private var updateCancellable: Any?
    private var didPlaceOnBody = false
    private var usingDebugRig = false
    private var debugTorso: BodyCapsuleRig.TorsoHandles?
    private var debugCapsules: [BodyCapsule] = []
    private var debugCamera = SIMD3<Float>(0, 1.4, 0.8)
    private var lastAppliedImage: UIImage?
    private var lastAppliedAspect: Float = -1

    override func loadView() {
        view = arView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.renderOptions.insert(.disableMotionBlur)
        arView.environment.lighting.intensityExponent = 0.55

        installLighting()
        arView.scene.addAnchor({
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(simulation.meshEntity)
            return anchor
        }())

        updateCancellable = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onSceneUpdate(deltaTime: event.deltaTime)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    /// Swap the cloth albedo without allocating a new entity. Aspect only re-inits
    /// the PBD sheet when it actually changes, so SwiftUI redraws are cheap.
    func setGarment(image: UIImage?, aspect: Float) {
        let imageChanged = lastAppliedImage !== image
        let aspectChanged = abs(lastAppliedAspect - aspect) > 1e-4
        if !imageChanged && !aspectChanged { return }
        lastAppliedImage = image
        lastAppliedAspect = aspect
        simulation.setPhotoAspect(aspect)
        simulation.meshEntity.applyTexture(image)
        if aspectChanged && aspect > 0 {
            simulation.requestGarmentReset()
        }
    }

    private func startSession() {
#if targetEnvironment(simulator)
        startDebugScene(reason: .simulator)
#else
        if ARBodyTrackingConfiguration.isSupported {
            let config = ARBodyTrackingConfiguration()
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            usingDebugRig = false
            DispatchQueue.main.async {
                self.status?.mode = .bodyTracking
                self.status?.detail = "Stand in frame so ARKit can lock a skeleton."
            }
        } else {
            startDebugScene(reason: .unsupported)
        }
#endif
    }

    private func startDebugScene(reason: SimulationStatus.Mode) {
        usingDebugRig = true
        didPlaceOnBody = true
        arView.cameraMode = .nonAR
        // Warm studio, not neon — cloth albedo has to read against it.
        arView.environment.background = .color(UIColor(red: 0.22, green: 0.20, blue: 0.16, alpha: 1))

        let (capsules, torso) = BodyCapsuleRig.tPoseStanding(at: SIMD3(0, 0, -2))
        debugCapsules = capsules
        debugTorso = torso
        simulation.ingest(capsules: capsules, torso: torso, cameraWorld: debugCamera, resetGarment: true)
        installDebugCamera(lookingAt: SIMD3(0, 1.2, -2))
        installDebugCapsuleVisuals(capsules)

        DispatchQueue.main.async {
            self.status?.mode = reason
            self.status?.bodyPresent = true
            self.status?.trackingState = "debug T-pose"
            self.status?.detail = reason == .simulator
                ? "ARKit body tracking does not run in Simulator. A standing T-pose capsule rig drives the cloth."
                : "This device cannot track a 3D body (needs A12+ iPhone/iPad with a rear camera). Debug T-pose rig is running."
        }
    }

    private func installLighting() {
        // Directional key light so the PBR roughness on the garment actually reads.
        // In AR this sits in world space and is a proxy; RealityKit still samples
        // the camera feed for IBL via environment.lighting.
        let sun = DirectionalLight()
        sun.light.color = .white
        sun.light.intensity = 1400
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 0.5)
        sun.look(at: SIMD3(0, 1.0, -2), from: SIMD3(1.2, 2.4, 0.4), relativeTo: nil)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(sun)
        arView.scene.addAnchor(anchor)
    }

    private func installDebugCamera(lookingAt target: SIMD3<Float>) {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 50
        camera.look(at: target, from: debugCamera, relativeTo: nil)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)
    }

    /// Faint unlit cylinders so the collision hull is visible in Simulator.
    private func installDebugCapsuleVisuals(_ capsules: [BodyCapsule]) {
        let anchor = AnchorEntity(world: .zero)
        let material = UnlitMaterial(color: UIColor(white: 1, alpha: 0.18))
        for cap in capsules {
            let delta = cap.b - cap.a
            let height = max(simd_length(delta), 0.02)
            // MeshResource has no generateCylinder on iOS 17; a Y-aligned box is a
            // faithful enough debug hull and is available on every RealityKit SDK.
            let mesh = MeshResource.generateBox(width: cap.radius * 2,
                                                height: height,
                                                depth: cap.radius * 2)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = (cap.a + cap.b) * 0.5
            // Cylinder is Y-aligned. Rotate so +Y matches the segment.
            let y = SIMD3<Float>(0, 1, 0)
            let dir = simd_normalize(delta)
            let axis = simd_cross(y, dir)
            let axisLen = simd_length(axis)
            if axisLen > 1e-5 {
                let angle = acos(max(-1, min(1, simd_dot(y, dir))))
                entity.orientation = simd_quatf(angle: angle, axis: axis / axisLen)
            }
            anchor.addChild(entity)
        }
        arView.scene.addAnchor(anchor)
    }

    private func onSceneUpdate(deltaTime: TimeInterval) {
        if usingDebugRig, let torso = debugTorso {
            simulation.ingest(capsules: debugCapsules, torso: torso, cameraWorld: debugCamera, resetGarment: false)
        } else if let frame = arView.session.currentFrame {
            let cam = frame.camera.transform.columns.3
            let cameraWorld = SIMD3<Float>(cam.x, cam.y, cam.z)
            if let body = frame.anchors.compactMap({ $0 as? ARBodyAnchor }).first,
               let torso = BodyCapsuleRig.torsoHandles(from: body) {
                let capsules = BodyCapsuleRig.capsules(from: body)
                let firstLock = !didPlaceOnBody
                didPlaceOnBody = true
                simulation.ingest(capsules: capsules,
                                  torso: torso,
                                  cameraWorld: cameraWorld,
                                  resetGarment: firstLock)
                if status?.bodyPresent != true {
                    DispatchQueue.main.async {
                        self.status?.bodyPresent = true
                        self.status?.detail = "Skeleton locked. Cloth is simulating in world meters."
                    }
                }
            }
        }
        simulation.tick(deltaTime: deltaTime)
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let label: String
        switch camera.trackingState {
        case .normal: label = "normal"
        case .notAvailable: label = "not available"
        case .limited(let reason):
            switch reason {
            case .initializing: label = "limited (initializing)"
            case .excessiveMotion: label = "limited (motion)"
            case .insufficientFeatures: label = "limited (features)"
            case .relocalizing: label = "limited (relocalizing)"
            @unknown default: label = "limited"
            }
        }
        DispatchQueue.main.async { self.status?.trackingState = label }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.status?.detail = "AR session failed: \(error.localizedDescription)"
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { self.status?.detail = "AR session interrupted" }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        startSession()
    }
}
