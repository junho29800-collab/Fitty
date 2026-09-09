import ARKit
import RealityKit
import SwiftUI
import UIKit

/// SwiftUI wrapper around the ARKit/RealityKit host.
struct ARViewController: UIViewControllerRepresentable {
    @ObservedObject var status: SimulationStatus
    @ObservedObject var settings: AppSettings
    var garmentImage: UIImage?
    var garmentBack: UIImage?
    var garmentAspect: Float
    var garmentKind: GarmentKind
    var snapshotToken: Int
    var onSnapshot: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> ARClothHostController {
        let host = ARClothHostController()
        host.status = status
        host.settings = settings
        host.onSnapshot = onSnapshot
        host.applyAll(image: garmentImage, back: garmentBack, aspect: garmentAspect, kind: garmentKind)
        return host
    }

    func updateUIViewController(_ uiViewController: ARClothHostController, context: Context) {
        uiViewController.status = status
        uiViewController.settings = settings
        uiViewController.onSnapshot = onSnapshot
        uiViewController.applyAll(image: garmentImage, back: garmentBack, aspect: garmentAspect, kind: garmentKind)
        uiViewController.handleSnapshot(token: snapshotToken)
        uiViewController.setDebugVisible(settings.debugOverlay)
        uiViewController.setQuality(settings.quality)
    }
}

final class ARClothHostController: UIViewController, ARSessionDelegate {

    let arView = ARView(frame: .zero)
    let simulation: ClothSimulationComponent
    var onSnapshot: ((UIImage?) -> Void)?
    var settings: AppSettings? {
        didSet { pushRuntime() }
    }

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
    private var lastAppliedBack: UIImage?
    private var lastAppliedAspect: Float = -1
    private var lastKind: GarmentKind?
    private var lastSnapshotToken = 0
    private var sun: DirectionalLight?
    private var debugAnchor: AnchorEntity?
    private var worldAnchor: AnchorEntity?
    private var lastQuality: SimQuality = .med
    private var lastSizeScale: GarmentSize?
    private var lastBodyScale: Float = -1

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    init() {
        simulation = ClothSimulationComponent(quality: AppSettings.shared.quality)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(simulation.meshEntity)
        worldAnchor = anchor
        simulation.meshParent = anchor
        arView.scene.addAnchor(anchor)

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

    func applyAll(image: UIImage?, back: UIImage?, aspect: Float, kind: GarmentKind) {
        let imageChanged = lastAppliedImage !== image || lastAppliedBack !== back
        let aspectChanged = abs(lastAppliedAspect - aspect) > 1e-4
        let kindChanged = lastKind != kind
        lastAppliedImage = image
        lastAppliedBack = back
        lastAppliedAspect = aspect
        lastKind = kind
        simulation.setPhotoAspect(aspect)
        let fabric = settings?.lastFabric ?? .cotton
        simulation.meshEntity.applyTexture(front: image,
                                           back: back,
                                           roughness: fabric.roughness,
                                           metallic: fabric.metallic,
                                           emissive: 0)
        if (aspectChanged && aspect > 0) || kindChanged {
            simulation.requestGarmentReset()
        }
        if imageChanged && !aspectChanged && !kindChanged {
            // texture-only swap (compare A/B)
        }
        pushRuntime()
        let sizeChanged = lastSizeScale != (settings?.lastSize ?? .m)
        let bodyChanged = abs(lastBodyScale - (settings?.bodyScale ?? 1)) > 0.001
        lastSizeScale = settings?.lastSize
        lastBodyScale = settings?.bodyScale ?? 1
        if imageChanged || kindChanged || sizeChanged || bodyChanged {
            simulation.requestGarmentReset()
        }
    }

    func handleSnapshot(token: Int) {
        guard token != lastSnapshotToken, token > 0 else { return }
        lastSnapshotToken = token
        arView.snapshot(saveToHDR: false) { [weak self] image in
            self?.onSnapshot?(image)
        }
    }

    func setDebugVisible(_ on: Bool) {
        debugAnchor?.isEnabled = on
    }

    func setQuality(_ quality: SimQuality) {
        if quality != lastQuality {
            lastQuality = quality
            simulation.setQuality(quality)
        }
    }

    private func pushRuntime() {
        guard let settings else { return }
        simulation.setRuntime(fabric: settings.lastFabric,
                              size: settings.lastSize,
                              kind: lastKind ?? .tee,
                              fitLength: settings.fitLength,
                              fitTightness: settings.fitTightness,
                              fitDrape: settings.fitDrape,
                              wind: settings.windVector,
                              bodyScale: settings.bodyScale)
        let fabric = settings.lastFabric
        simulation.meshEntity.applyTexture(front: lastAppliedImage,
                                           back: lastAppliedBack,
                                           roughness: fabric.roughness,
                                           metallic: fabric.metallic,
                                           emissive: 0)
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
        arView.environment.background = .color(UIColor(red: 0.22, green: 0.20, blue: 0.16, alpha: 1))

        let scale = settings?.bodyScale ?? 1
        let (capsules, torso) = BodyCapsuleRig.tPoseStanding(at: SIMD3(0, 0, -2), scale: scale)
        debugCapsules = capsules
        debugTorso = torso
        let ellipsoids = BodyCapsuleRig.volumeEllipsoids(torso: torso, cameraWorld: debugCamera, scale: scale)
        let arms = BodyCapsuleRig.upperArmCapsulesTPose(torso: torso, scale: scale)
        simulation.ingest(capsules: capsules, ellipsoids: ellipsoids, arms: arms,
                          torso: torso, cameraWorld: debugCamera, resetGarment: true)
        installDebugCamera(lookingAt: SIMD3(0, 1.2, -2))
        installDebugCapsuleVisuals(capsules)
        debugAnchor?.isEnabled = settings?.debugOverlay ?? false

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
        let sun = DirectionalLight()
        sun.light.color = .white
        sun.light.intensity = 1400
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 0.5)
        sun.look(at: SIMD3(0, 1.0, -2), from: SIMD3(1.2, 2.4, 0.4), relativeTo: nil)
        self.sun = sun
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(sun)
        arView.scene.addAnchor(anchor)
    }

    private func applyLightEstimate(_ estimate: ARLightEstimate) {
        guard let sun else { return }
        // ARKit ambientIntensity is lumens; ~1000 is a typical indoor default.
        let intensity = Float(estimate.ambientIntensity)
        sun.light.intensity = max(400, min(intensity, 2500))
        let temp = CGFloat(estimate.ambientColorTemperature)
        sun.light.color = Self.color(fromKelvin: temp)
        let ambientBoost = max(0, min((intensity / 1000.0) * 0.06, 0.18))
        simulation.meshEntity.setEmissive(ambientBoost)
        arView.environment.lighting.intensityExponent = 0.4 + (intensity / 1000.0) * 0.25
    }

    private static func color(fromKelvin kelvin: CGFloat) -> UIColor {
        let k = max(1000, min(kelvin, 12000)) / 100
        var r, g, b: CGFloat
        if k <= 66 {
            r = 1
            g = max(0, min(1, 0.39008157876 * log(k) - 0.63184144378))
            b = k <= 19 ? 0 : max(0, min(1, 0.54320678911 * log(k - 10) - 1.19625408914))
        } else {
            r = max(0, min(1, 1.29293618606 * pow(k - 60, -0.1332047592)))
            g = max(0, min(1, 1.12989086089 * pow(k - 60, -0.0755148492)))
            b = 1
        }
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private func installDebugCamera(lookingAt target: SIMD3<Float>) {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 50
        camera.look(at: target, from: debugCamera, relativeTo: nil)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)
    }

    private func installDebugCapsuleVisuals(_ capsules: [BodyCapsule]) {
        debugAnchor?.removeFromParent()
        let anchor = AnchorEntity(world: .zero)
        let material = UnlitMaterial(color: UIColor(white: 1, alpha: 0.18))
        for cap in capsules {
            let delta = cap.b - cap.a
            let height = max(simd_length(delta), 0.02)
            let mesh = MeshResource.generateBox(width: cap.radius * 2,
                                                height: height,
                                                depth: cap.radius * 2)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = (cap.a + cap.b) * 0.5
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
        debugAnchor = anchor
        anchor.isEnabled = settings?.debugOverlay ?? false
    }

    private func onSceneUpdate(deltaTime: TimeInterval) {
        if let settings, let kind = lastKind {
            simulation.setRuntime(fabric: settings.lastFabric,
                                  size: settings.lastSize,
                                  kind: kind,
                                  fitLength: settings.fitLength,
                                  fitTightness: settings.fitTightness,
                                  fitDrape: settings.fitDrape,
                                  wind: settings.windVector,
                                  bodyScale: settings.bodyScale)
        }
        let scale = settings?.bodyScale ?? 1
        if usingDebugRig, let torso = debugTorso {
            let ellipsoids = BodyCapsuleRig.volumeEllipsoids(torso: torso, cameraWorld: debugCamera, scale: scale)
            let arms = BodyCapsuleRig.upperArmCapsulesTPose(torso: torso, scale: scale)
            simulation.ingest(capsules: debugCapsules, ellipsoids: ellipsoids, arms: arms,
                              torso: torso, cameraWorld: debugCamera, resetGarment: false)
        } else if let frame = arView.session.currentFrame {
            if let estimate = frame.lightEstimate {
                applyLightEstimate(estimate)
            }
            let cam = frame.camera.transform.columns.3
            let cameraWorld = SIMD3<Float>(cam.x, cam.y, cam.z)
            if let body = frame.anchors.compactMap({ $0 as? ARBodyAnchor }).first,
               let torso = BodyCapsuleRig.torsoHandles(from: body) {
                let capsules = BodyCapsuleRig.capsules(from: body, scale: scale)
                let ellipsoids = BodyCapsuleRig.volumeEllipsoids(torso: torso, cameraWorld: cameraWorld, scale: scale)
                let arms = BodyCapsuleRig.upperArmCapsules(from: body, scale: scale)
                let firstLock = !didPlaceOnBody
                didPlaceOnBody = true
                simulation.ingest(capsules: capsules, ellipsoids: ellipsoids, arms: arms,
                                  torso: torso, cameraWorld: cameraWorld, resetGarment: firstLock)
                if settings?.debugOverlay == true {
                    installDebugCapsuleVisuals(capsules)
                }
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
