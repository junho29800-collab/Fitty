import UIKit

/// Caps PNG/JPEG size on disk so a wardrobe of 30 scans stays reasonable.
enum ImageIOSupport {
    static let maxDimension: CGFloat = 1600
    static let maxBytes = 1_400_000

    /// GPU albedo cap. iPhone 1024, iPad 2048. Keeps aspect.
    static var textureMaxDimension: CGFloat {
        DeviceProfile.shared.textureMaxDimension
    }

    static func cappedForTexture(_ image: UIImage) -> UIImage {
        scaled(image, maxDimension: textureMaxDimension)
    }

    static func compressedPNG(_ image: UIImage) -> Data? {
        let scaled = scaled(image, maxDimension: maxDimension)
        if let png = scaled.pngData(), png.count <= maxBytes {
            return png
        }
        // Fall back to JPEG when PNG is huge (photos from the picker). Alpha is lost;
        // isolation already flattened the interesting pixels onto transparency-or-cream.
        var quality: CGFloat = 0.82
        while quality >= 0.4 {
            if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
            quality -= 0.12
        }
        return scaled.jpegData(compressionQuality: 0.4) ?? scaled.pngData()
    }

    static func scaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        if longest <= maxDimension || longest <= 0 { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Side-by-side atlas: left = front, right = back. Used because RealityKit PBR
    /// cannot bind a different texture to the back faces of a single material.
    static func atlas(front: UIImage, back: UIImage) -> UIImage? {
        let h = max(front.size.height, back.size.height)
        let fw = front.size.width * (h / max(front.size.height, 1))
        let bw = back.size.width * (h / max(back.size.height, 1))
        let size = CGSize(width: fw + bw, height: h)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            front.draw(in: CGRect(x: 0, y: 0, width: fw, height: h))
            back.draw(in: CGRect(x: fw, y: 0, width: bw, height: h))
        }
    }
}
