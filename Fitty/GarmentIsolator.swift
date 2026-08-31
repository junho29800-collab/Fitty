import CoreImage
import UIKit
import Vision

/// Lifts the garment off the background using Vision subject lifting (iOS 17+).
///
/// Exact types (WWDC23 / iOS 17 SDK):
/// * `VNGenerateForegroundInstanceMaskRequest` — class-agnostic foreground instances.
/// * Result is `VNInstanceMaskObservation`.
/// * `generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)` returns a
///   high-resolution `CVPixelBuffer` with transparent black background.
///
/// If the request throws, returns no instances, or the buffer cannot be converted,
/// the full original image is returned so the user can still confirm.
enum GarmentIsolator {

    struct Outcome {
        var image: UIImage
        var isolationSucceeded: Bool
        /// Width / height of the image that will be UV-mapped onto the cloth sheet.
        var aspectRatio: CGFloat
    }

    static func isolate(_ image: UIImage) -> Outcome {
        let fallbackAspect = aspect(of: image)
        guard let cg = uprightCGImage(from: image) else {
            return Outcome(image: image, isolationSucceeded: false, aspectRatio: fallbackAspect)
        }

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNInstanceMaskObservation else {
                return Outcome(image: image, isolationSucceeded: false, aspectRatio: fallbackAspect)
            }
            // Crop to the subject so a shirt on a table fills the PBD UV square
            // instead of leaving a huge empty margin around it.
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            guard let lifted = uiImage(from: buffer) else {
                return Outcome(image: image, isolationSucceeded: false, aspectRatio: fallbackAspect)
            }
            return Outcome(image: lifted, isolationSucceeded: true, aspectRatio: aspect(of: lifted))
        } catch {
            return Outcome(image: image, isolationSucceeded: false, aspectRatio: fallbackAspect)
        }
    }

    static func aspect(of image: UIImage) -> CGFloat {
        let h = image.size.height
        if h <= 0 { return 1 }
        return image.size.width / h
    }

    /// Draw through UIKit so `.left` / `.right` / `.down` camera frames become `.up`
    /// before Vision sees them. Vision's `orientation: .up` then matches pixels.
    static func uprightCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return drawn.cgImage ?? image.cgImage
    }

    static func uiImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}
