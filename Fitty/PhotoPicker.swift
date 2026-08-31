import PhotosUI
import SwiftUI
import UIKit

/// PHPicker wrapper. Images only, selectionLimit 1.
/// PHPicker does **not** require a photo-library usage string — do not add NSPhotoLibrary*.
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (UIImage) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [onPick, onCancel] object, _ in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            onPick(image)
                        } else {
                            onCancel()
                        }
                    }
                }
            } else {
                onCancel()
            }
        }
    }
}
