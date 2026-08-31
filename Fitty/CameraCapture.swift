import AVFoundation
import SwiftUI
import UIKit

/// Boxy camera preview + still capture. Simulator has no capture device — `isAvailable`
/// stays false and ScanView routes the user to PHPicker.
final class CameraHostController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private(set) var lastShutterToken = 0

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.junholee.Fitty.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FittyTheme.uiInk
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func fireShutter(token: Int) {
        guard token != lastShutterToken else { return }
        lastShutterToken = token
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.onAvailability?(false) }
            return
        }
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        configured = true
        session.startRunning()
        DispatchQueue.main.async { self.onAvailability?(true) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            return
        }
        DispatchQueue.main.async { self.onCapture?(image) }
    }
}

struct CameraViewfinder: UIViewControllerRepresentable {
    var shutterToken: Int
    var onCapture: (UIImage) -> Void
    var onAvailability: (Bool) -> Void

    func makeUIViewController(context: Context) -> CameraHostController {
        let host = CameraHostController()
        host.onCapture = onCapture
        host.onAvailability = onAvailability
        return host
    }

    func updateUIViewController(_ uiViewController: CameraHostController, context: Context) {
        uiViewController.onCapture = onCapture
        uiViewController.onAvailability = onAvailability
        uiViewController.fireShutter(token: shutterToken)
    }
}
