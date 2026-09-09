import ReplayKit
import UIKit

/// 8-second try-on clip via ReplayKit. Microphone stays off. Permission deny is
/// surfaced as a toast; the share sheet (RPPreview) is enough — no Photo Library write.
final class ClipRecorder: NSObject, RPPreviewViewControllerDelegate, ObservableObject {
    static let shared = ClipRecorder()
    @Published var isRecording = false
    private var stopWork: DispatchWorkItem?
    private weak var presenter: UIViewController?

    var duration: TimeInterval = 8

    func toggle(from presenter: UIViewController) {
        if isRecording {
            stop()
        } else {
            start(from: presenter)
        }
    }

    func start(from presenter: UIViewController) {
        if DeviceProfile.shared.skipReplayKit {
            ToastCenter.shared.show(L10n.t("tryOn.recordCooling"))
            return
        }
        self.presenter = presenter
        let rec = RPScreenRecorder.shared()
        rec.isMicrophoneEnabled = false
        guard rec.isAvailable else {
            ToastCenter.shared.show(L10n.t("tryOn.recordDenied"))
            return
        }
        rec.startRecording { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    ToastCenter.shared.show(L10n.t("tryOn.recordDenied"))
                    print("Fitty ReplayKit start: \(error.localizedDescription)")
                    return
                }
                self?.isRecording = true
                let work = DispatchWorkItem { self?.stop() }
                self?.stopWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (self?.duration ?? 8), execute: work)
            }
        }
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        guard isRecording else { return }
        RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
            DispatchQueue.main.async {
                self?.isRecording = false
                if let error {
                    ToastCenter.shared.show(L10n.t("tryOn.recordFailed"))
                    print("Fitty ReplayKit stop: \(error.localizedDescription)")
                    return
                }
                guard let preview else {
                    ToastCenter.shared.show(L10n.t("tryOn.recordFailed"))
                    return
                }
                preview.previewControllerDelegate = self
                preview.modalPresentationStyle = .fullScreen
                self?.presenter?.present(preview, animated: true)
                ToastCenter.shared.show(L10n.t("tryOn.recordDone"))
            }
        }
    }

    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }
}
