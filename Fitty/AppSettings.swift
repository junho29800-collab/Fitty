import Combine
import Foundation
import SwiftUI
import UIKit

/// Fabric presets drive C++ mass/damping/stretch/shear/bend/friction/XPBD α
/// AND Swift PBR roughness/metallic. Cotton is the default.
enum FabricPreset: String, CaseIterable, Identifiable {
    case cotton, silk, denim, knit, linen
    var id: String { rawValue }

    var locKey: String { "fabric.\(rawValue)" }

    /// C++ solver knobs. Units: kg, dimensionless, XPBD α in m/N.
    var physics: (mass: Float, damping: Float, stretch: Float, shear: Float, bend: Float, friction: Float, xpbd: Float) {
        switch self {
        case .cotton: return (0.020, 0.04, 1.00, 0.85, 0.35, 0.35, 1.0e-5)
        case .silk:   return (0.012, 0.02, 0.40, 0.55, 0.18, 0.18, 3.0e-4)
        case .denim:  return (0.035, 0.08, 1.00, 0.95, 0.70, 0.55, 1.0e-6)
        case .knit:   return (0.018, 0.06, 0.55, 0.50, 0.22, 0.40, 8.0e-5)
        case .linen:  return (0.022, 0.05, 0.90, 0.80, 0.45, 0.30, 2.0e-5)
        }
    }

    var roughness: Float {
        switch self {
        case .cotton: return 0.55
        case .silk:   return 0.18
        case .denim:  return 0.72
        case .knit:   return 0.62
        case .linen:  return 0.58
        }
    }

    var metallic: Float {
        switch self {
        case .cotton: return 0.02
        case .silk:   return 0.08
        case .denim:  return 0.01
        case .knit:   return 0.02
        case .linen:  return 0.03
        }
    }
}

/// Kind changes pinning. Tee/hoodie: shoulder row. Pants: hip row kinematic.
/// Dress: shoulders + longer V. Tank: narrower U.
enum GarmentKind: String, CaseIterable, Identifiable {
    case tee, tank, hoodie, dress, pants
    var id: String { rawValue }
    var locKey: String { "kind.\(rawValue)" }

    /// Matches fitty::PinMode.
    var pinMode: Int32 {
        switch self {
        case .tee: return 0
        case .tank: return 1
        case .hoodie: return 2
        case .dress: return 3
        case .pants: return 4
        }
    }
}

enum GarmentSize: String, CaseIterable, Identifiable {
    case xs, s, m, l, xl, xxl
    var id: String { rawValue }
    var locKey: String { "size.\(rawValue)" }
    var label: String { rawValue.uppercased() }

    /// Uniform scale on rest garment width/length. Clamped in C++ to [0.72, 1.40].
    var scale: Float {
        switch self {
        case .xs: return 0.85
        case .s:  return 0.92
        case .m:  return 1.00
        case .l:  return 1.08
        case .xl: return 1.16
        case .xxl: return 1.28
        }
    }
}

enum SimQuality: String, CaseIterable, Identifiable {
    case low, med, high
    var id: String { rawValue }
    var locKey: String { "quality.\(rawValue)" }

    var width: Int {
        switch self {
        case .low: return 16
        case .med: return 24
        case .high: return 32
        }
    }

    var height: Int {
        switch self {
        case .low: return 20
        case .med: return 32
        case .high: return 40
        }
    }

    var spacing: Float {
        switch self {
        case .low: return 0.024
        case .med: return 0.018
        case .high: return 0.014
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case device, en, ko
    var id: String { rawValue }
    var locKey: String { "lang.\(rawValue)" }
}

enum WardrobeSort: String {
    case newest, name
}

enum AppUnits: String, CaseIterable, Identifiable {
    case meters, centimeters
    var id: String { rawValue }
    var locKey: String { "units.\(rawValue)" }
}

/// Persisted settings + last try-on choices. Survive cold start via UserDefaults.
/// Local auth lives in AuthStore/Keychain; settings themselves are UserDefaults, no iCloud.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    @Published var quality: SimQuality {
        didSet { d.set(quality.rawValue, forKey: "fitty.quality") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { d.set(hapticsEnabled, forKey: "fitty.haptics") }
    }
    @Published var units: AppUnits {
        didSet { d.set(units.rawValue, forKey: "fitty.units") }
    }
    @Published var language: AppLanguage {
        didSet { d.set(language.rawValue, forKey: "fitty.language") }
    }
    @Published var debugOverlay: Bool {
        didSet { d.set(debugOverlay, forKey: "fitty.debug") }
    }
    @Published var fabricDefault: FabricPreset {
        didSet { d.set(fabricDefault.rawValue, forKey: "fitty.fabricDefault") }
    }
    @Published var lastFabric: FabricPreset {
        didSet { d.set(lastFabric.rawValue, forKey: "fitty.lastFabric") }
    }
    @Published var lastSize: GarmentSize {
        didSet { d.set(lastSize.rawValue, forKey: "fitty.lastSize") }
    }
    @Published var scanCountdown: Bool {
        didSet { d.set(scanCountdown, forKey: "fitty.countdown") }
    }
    @Published var onboardingDone: Bool {
        didSet { d.set(onboardingDone, forKey: "fitty.onboardingDone") }
    }
    @Published var heightCm: Int {
        didSet { d.set(heightCm, forKey: "fitty.heightCm") }
    }
    @Published var fitLength: Float {
        didSet { d.set(fitLength, forKey: "fitty.fitLength") }
    }
    @Published var fitTightness: Float {
        didSet { d.set(fitTightness, forKey: "fitty.fitTightness") }
    }
    @Published var fitDrape: Float {
        didSet { d.set(fitDrape, forKey: "fitty.fitDrape") }
    }
    @Published var windStrength: Float {
        didSet { d.set(windStrength, forKey: "fitty.windStrength") }
    }
    /// Radians in XZ, 0 = +X.
    @Published var windAngle: Float {
        didSet { d.set(windAngle, forKey: "fitty.windAngle") }
    }
    @Published var wardrobeSort: WardrobeSort {
        didSet { d.set(wardrobeSort.rawValue, forKey: "fitty.wardrobeSort") }
    }

    var bodyScale: Float {
        Float(heightCm) / 170.0
    }

    var windVector: SIMD3<Float> {
        SIMD3(cos(windAngle) * windStrength, 0, sin(windAngle) * windStrength)
    }

    var resolvedLang: String {
        switch language {
        case .en: return "en"
        case .ko: return "ko"
        case .device:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("ko") ? "ko" : "en"
        }
    }

    var appVersion: String { "0.2.0" }

    init() {
        func str(_ k: String, _ fallback: String) -> String {
            d.string(forKey: k) ?? fallback
        }
        let fallbackQ = UIDevice.current.userInterfaceIdiom == .phone ? "low" : "med"
        quality = SimQuality(rawValue: str("fitty.quality", fallbackQ)) ?? (fallbackQ == "low" ? .low : .med)
        hapticsEnabled = d.object(forKey: "fitty.haptics") as? Bool ?? true
        units = AppUnits(rawValue: str("fitty.units", "centimeters")) ?? .centimeters
        language = AppLanguage(rawValue: str("fitty.language", "device")) ?? .device
        debugOverlay = d.bool(forKey: "fitty.debug")
        fabricDefault = FabricPreset(rawValue: str("fitty.fabricDefault", "cotton")) ?? .cotton
        lastFabric = FabricPreset(rawValue: str("fitty.lastFabric", fabricDefault.rawValue)) ?? fabricDefault
        lastSize = GarmentSize(rawValue: str("fitty.lastSize", "m")) ?? .m
        scanCountdown = d.bool(forKey: "fitty.countdown")
        onboardingDone = d.bool(forKey: "fitty.onboardingDone")
        let h = d.integer(forKey: "fitty.heightCm")
        heightCm = h == 0 ? 170 : min(200, max(150, h))
        let len = d.object(forKey: "fitty.fitLength") as? Float
        fitLength = len ?? 1
        let tight = d.object(forKey: "fitty.fitTightness") as? Float
        fitTightness = tight ?? 1
        let drape = d.object(forKey: "fitty.fitDrape") as? Float
        fitDrape = drape ?? 1
        let wind = d.object(forKey: "fitty.windStrength") as? Float
        windStrength = wind ?? 0
        let ang = d.object(forKey: "fitty.windAngle") as? Float
        windAngle = ang ?? 0
        wardrobeSort = WardrobeSort(rawValue: str("fitty.wardrobeSort", "newest")) ?? .newest
    }

    func resetOnboarding() {
        onboardingDone = false
    }
}
