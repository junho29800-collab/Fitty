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
    var name: String
    var notes: String
    var kind: GarmentKind
    var hasBack: Bool

    var frontURL: URL { directory.appendingPathComponent("front.png") }
    var backURL: URL { directory.appendingPathComponent("back.png") }
    var metaURL: URL { directory.appendingPathComponent("meta.json") }

    func loadFront() -> UIImage? {
        guard let data = try? Data(contentsOf: frontURL) else { return nil }
        return UIImage(data: data)
    }

    func loadBack() -> UIImage? {
        guard hasBack, let data = try? Data(contentsOf: backURL) else { return nil }
        return UIImage(data: data)
    }
}

/// Local-only garment library. No accounts, catalog, or networking.
/// Cap 30; oldest evicted with a toast. Selected id + last fabric/size live in AppSettings.
final class GarmentStore: ObservableObject {
    static let maxCount = 30

    @Published private(set) var garments: [Garment] = []
    @Published var selectedID: UUID? {
        didSet {
            if let id = selectedID {
                UserDefaults.standard.set(id.uuidString, forKey: "fitty.lastGarment")
            }
            refreshSelectedImages()
        }
    }
    @Published private(set) var selectedFrontImage: UIImage?
    @Published private(set) var selectedBackImage: UIImage?
    @Published var lastEvictionNotice: String?

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
        applySort(&loaded)
        garments = loaded
        if let saved = UserDefaults.standard.string(forKey: "fitty.lastGarment"),
           let id = UUID(uuidString: saved),
           loaded.contains(where: { $0.id == id }) {
            selectedID = id
        } else if selectedID == nil {
            selectedID = loaded.first?.id
        }
        refreshSelectedImages()
    }

    func sortedGarments(by sort: WardrobeSort) -> [Garment] {
        var copy = garments
        switch sort {
        case .newest: copy.sort { $0.created > $1.created }
        case .name: copy.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return copy
    }

    @discardableResult
    func save(front: UIImage,
              back: UIImage?,
              isolationSucceeded: Bool,
              aspectRatio: CGFloat,
              kind: GarmentKind,
              name: String? = nil) -> Garment? {
        evictIfNeeded()
        let id = UUID()
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try writeImage(front, to: dir.appendingPathComponent("front.png"))
            var hasBack = false
            if let back {
                try writeImage(back, to: dir.appendingPathComponent("back.png"))
                hasBack = true
            }
            let created = Date()
            let garment = Garment(id: id,
                                  created: created,
                                  aspectRatio: aspectRatio,
                                  isolationSucceeded: isolationSucceeded,
                                  directory: dir,
                                  name: name ?? defaultName(kind: kind, date: created),
                                  notes: "",
                                  kind: kind,
                                  hasBack: hasBack)
            try writeMeta(garment)
            garments.insert(garment, at: 0)
            selectedID = id
            selectedFrontImage = front
            selectedBackImage = back
            return garment
        } catch {
            ToastCenter.shared.show(L10n.t("scan.saveFailed"))
            return nil
        }
    }

    /// Rescan: keep the wardrobe entry, replace photos (S19).
    @discardableResult
    func updatePhotos(id: UUID,
                      front: UIImage,
                      back: UIImage?,
                      isolationSucceeded: Bool,
                      aspectRatio: CGFloat,
                      kind: GarmentKind) -> Garment? {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else {
            return save(front: front, back: back, isolationSucceeded: isolationSucceeded, aspectRatio: aspectRatio, kind: kind)
        }
        var g = garments[idx]
        do {
            try writeImage(front, to: g.frontURL)
            if let back {
                try writeImage(back, to: g.backURL)
                g.hasBack = true
            } else if g.hasBack {
                try? FileManager.default.removeItem(at: g.backURL)
                g.hasBack = false
            }
            g.isolationSucceeded = isolationSucceeded
            g.aspectRatio = aspectRatio
            g.kind = kind
            try writeMeta(g)
            garments[idx] = g
            selectedID = g.id
            selectedFrontImage = front
            selectedBackImage = back
            return g
        } catch {
            ToastCenter.shared.show(L10n.t("scan.saveFailed"))
            return nil
        }
    }

    func select(_ id: UUID) {
        selectedID = id
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        var g = garments[idx]
        g.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if g.name.isEmpty { g.name = defaultName(kind: g.kind, date: g.created) }
        garments[idx] = g
        try? writeMeta(g)
        objectWillChange.send()
    }

    func setNotes(_ id: UUID, notes: String) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        var g = garments[idx]
        g.notes = notes
        garments[idx] = g
        try? writeMeta(g)
    }

    func setKind(_ id: UUID, kind: GarmentKind) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        var g = garments[idx]
        g.kind = kind
        garments[idx] = g
        try? writeMeta(g)
        objectWillChange.send()
    }

    func delete(_ id: UUID) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        let g = garments[idx]
        try? FileManager.default.removeItem(at: g.directory)
        garments.remove(at: idx)
        if selectedID == id {
            selectedID = garments.first?.id
        }
        refreshSelectedImages()
    }

    private func evictIfNeeded() {
        lastEvictionNotice = nil
        while garments.count >= Self.maxCount {
            let oldest = garments.min(by: { $0.created < $1.created })
            guard let oldest else { break }
            try? FileManager.default.removeItem(at: oldest.directory)
            garments.removeAll { $0.id == oldest.id }
            lastEvictionNotice = L10n.t("wardrobe.evicted")
            ToastCenter.shared.show(L10n.t("wardrobe.evicted"))
        }
    }

    private func writeImage(_ image: UIImage, to url: URL) throws {
        guard let data = ImageIOSupport.compressedPNG(image) else {
            throw NSError(domain: "Fitty", code: 1, userInfo: [NSLocalizedDescriptionKey: "encode"])
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeMeta(_ g: Garment) throws {
        let meta: [String: Any] = [
            "id": g.id.uuidString,
            "created": iso.string(from: g.created),
            "aspectRatio": Double(g.aspectRatio),
            "isolationSucceeded": g.isolationSucceeded,
            "name": g.name,
            "notes": g.notes,
            "kind": g.kind.rawValue,
            "hasBack": g.hasBack
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
        try data.write(to: g.metaURL, options: .atomic)
    }

    private func refreshSelectedImages() {
        selectedFrontImage = selected?.loadFront()
        selectedBackImage = selected?.loadBack()
    }

    private func applySort(_ loaded: inout [Garment]) {
        loaded.sort { $0.created > $1.created }
    }

    private func defaultName(kind: GarmentKind, date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return "\(L10n.t(kind.locKey)) · \(f.string(from: date))"
    }

    private func readMeta(in dir: URL) -> Garment? {
        let metaURL = dir.appendingPathComponent("meta.json")
        let frontURL = dir.appendingPathComponent("front.png")
        let jpegFront = dir.appendingPathComponent("front.jpg")
        let frontExists = FileManager.default.fileExists(atPath: frontURL.path)
            || FileManager.default.fileExists(atPath: jpegFront.path)
        guard frontExists,
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
        let kind = GarmentKind(rawValue: (obj["kind"] as? String) ?? "tee") ?? .tee
        let hasBack = (obj["hasBack"] as? Bool) ?? FileManager.default.fileExists(atPath: dir.appendingPathComponent("back.png").path)
        let name = (obj["name"] as? String) ?? defaultName(kind: kind, date: created)
        let notes = (obj["notes"] as? String) ?? ""
        return Garment(id: id,
                       created: created,
                       aspectRatio: aspect > 0 ? aspect : 1,
                       isolationSucceeded: isolated,
                       directory: dir,
                       name: name,
                       notes: notes,
                       kind: kind,
                       hasBack: hasBack)
    }
}
