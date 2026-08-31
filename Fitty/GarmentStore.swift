import Combine
import Foundation
import UIKit

/// One scanned (or picked) garment persisted under Documents/Garments/<uuid>/.
struct Garment: Identifiable, Equatable {
    var id: UUID
    var created: Date
    var aspectRatio: CGFloat
    var isolationSucceeded: Bool
    var directory: URL

    var frontURL: URL { directory.appendingPathComponent("front.png") }
    var metaURL: URL { directory.appendingPathComponent("meta.json") }

    func loadFront() -> UIImage? {
        guard let data = try? Data(contentsOf: frontURL) else { return nil }
        return UIImage(data: data)
    }
}

/// Local-only garment library. No accounts, catalog, or networking.
final class GarmentStore: ObservableObject {
    @Published private(set) var garments: [Garment] = []
    @Published var selectedID: UUID?
    @Published private(set) var selectedFrontImage: UIImage?

    var selected: Garment? {
        if let id = selectedID, let match = garments.first(where: { $0.id == id }) {
            return match
        }
        return garments.first
    }

    private let root: URL
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(fileManager: FileManager = .default) {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        root = docs.appendingPathComponent("Garments", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            garments = []
            return
        }
        var loaded: [Garment] = []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let garment = readMeta(in: dir) else { continue }
            loaded.append(garment)
        }
        loaded.sort { $0.created > $1.created }
        garments = loaded
        if selectedID == nil {
            selectedID = loaded.first?.id
        }
        refreshSelectedImage()
    }

    @discardableResult
    func save(front: UIImage, isolationSucceeded: Bool, aspectRatio: CGFloat) -> Garment? {
        let id = UUID()
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let png = front.pngData() else { return nil }
            try png.write(to: dir.appendingPathComponent("front.png"), options: .atomic)
            let created = Date()
            let meta: [String: Any] = [
                "id": id.uuidString,
                "created": iso.string(from: created),
                "aspectRatio": Double(aspectRatio),
                "isolationSucceeded": isolationSucceeded
            ]
            let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
            try data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
            let garment = Garment(id: id,
                                  created: created,
                                  aspectRatio: aspectRatio,
                                  isolationSucceeded: isolationSucceeded,
                                  directory: dir)
            garments.insert(garment, at: 0)
            selectedID = id
            selectedFrontImage = front
            return garment
        } catch {
            return nil
        }
    }

    func select(_ id: UUID) {
        selectedID = id
        refreshSelectedImage()
    }

    private func refreshSelectedImage() {
        selectedFrontImage = selected?.loadFront()
    }

    private func readMeta(in dir: URL) -> Garment? {
        let metaURL = dir.appendingPathComponent("meta.json")
        let frontURL = dir.appendingPathComponent("front.png")
        guard FileManager.default.fileExists(atPath: frontURL.path),
              let data = try? Data(contentsOf: metaURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id: UUID
        if let raw = obj["id"] as? String, let parsed = UUID(uuidString: raw) {
            id = parsed
        } else if let parsed = UUID(uuidString: dir.lastPathComponent) {
            id = parsed
        } else {
            return nil
        }
        let created: Date
        if let raw = obj["created"] as? String, let parsed = iso.date(from: raw) {
            created = parsed
        } else {
            created = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        }
        let aspect = CGFloat((obj["aspectRatio"] as? Double) ?? 1)
        let isolated = (obj["isolationSucceeded"] as? Bool) ?? false
        return Garment(id: id,
                       created: created,
                       aspectRatio: aspect > 0 ? aspect : 1,
                       isolationSucceeded: isolated,
                       directory: dir)
    }
}
