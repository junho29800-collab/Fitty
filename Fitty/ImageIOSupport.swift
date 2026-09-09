import UIKit

/// Caps PNG/JPEG size on disk so a wardrobe of 30 scans stays reasonable.
enum ImageIOSupport {
    static let maxDimension: CGFloat = 1600
    static let maxBytes = 1_400_000

    enum Encoded {
        case png(Data)
        case jpeg(Data)

        var data: Data {
            switch self {
            case .png(let d), .jpeg(let d): return d
            }
        }

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }

    /// GPU albedo cap. iPhone 1024, iPad 2048. Keeps aspect.
    static var textureMaxDimension: CGFloat {
        DeviceProfile.shared.textureMaxDimension
    }

    static func cappedForTexture(_ image: UIImage) -> UIImage {
        scaled(image, maxDimension: textureMaxDimension)
    }

    static func hasAlpha(_ image: UIImage) -> Bool {
        guard let info = image.cgImage?.alphaInfo else { return false }
        switch info {
        case .none, .noneSkipLast, .noneSkipFirst: return false
        default: return true
        }
    }

    /// PNG when the image has a Vision mask (alpha). JPEG only for opaque photos,
    /// and never written under a `.png` name — callers use `fileExtension`.
    static func compressed(_ image: UIImage, keepAlpha: Bool) -> Encoded? {
        let preserveAlpha = keepAlpha || hasAlpha(image)
        var dim = maxDimension
        var current = scaled(image, maxDimension: dim)
        if preserveAlpha {
            while dim >= 256 {
                if let png = current.pngData(), png.count <= maxBytes {
                    return .png(png)
                }
                dim = floor(dim * 0.75)
                current = scaled(image, maxDimension: max(256, dim))
            }
            return current.pngData().map { .png($0) }
        }
        if let png = current.pngData(), png.count <= maxBytes {
            return .png(png)
        }
        var quality: CGFloat = 0.82
        while quality >= 0.4 {
            if let jpeg = current.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return .jpeg(jpeg)
            }
            quality -= 0.12
        }
        if let jpeg = current.jpegData(compressionQuality: 0.4) {
            return .jpeg(jpeg)
        }
        return current.pngData().map { .png($0) }
    }

    /// Snapshots stay PNG so the AR view keeps its alpha.
    static func compressedPNG(_ image: UIImage) -> Data? {
        compressed(image, keepAlpha: true)?.data
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
