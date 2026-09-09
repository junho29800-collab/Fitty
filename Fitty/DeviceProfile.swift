import Combine
import Foundation
import simd
import UIKit

/// Device class + thermal / Low Power policy. Physics still runs on `com.junholee.Fitty.pbd`.
/// Defaults: iPhone Low 16×20, iPad Med 24×32. Settings can still raise quality.
final class DeviceProfile: ObservableObject {
    static let shared = DeviceProfile()

    let isPhone: Bool
    @Published private(set) var isLowPower: Bool
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    @Published private(set) var isForeground: Bool = true

    /// Set when the user picks a quality in Settings this session.
    private(set) var userLockedQuality = false
    /// Hz auto-step floor (once per session unless the user overrides).
    private(set) var sessionStepDown: SimQuality?
    private var didAutoStepThisSession = false
    private var didToastCooling = false
    private var observers: [NSObjectProtocol] = []

    var defaultQuality: SimQuality { isPhone ? .low : .med }

    var textureMaxDimension: CGFloat { isPhone ? 1024 : 2048 }

    var isThermalStressed: Bool {
        switch thermalState {
        case .fair, .serious, .critical: return true
        case .nominal: return false
        @unknown default: return false
        }
    }

    var shouldThrottle: Bool { isThermalStressed || isLowPower }

    var skipReplayKit: Bool { shouldThrottle }

    var thermalLabelKey: String {
        switch thermalState {
        case .nominal: return "settings.thermal.nominal"
        case .fair: return "settings.thermal.fair"
        case .serious: return "settings.thermal.serious"
        case .critical: return "settings.thermal.critical"
        @unknown default: return "settings.thermal.unknown"
        }
    }

    private init() {
        isPhone = UIDevice.current.userInterfaceIdiom == .phone
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
        startObserving()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func setForeground(_ active: Bool) {
        if isForeground != active {
            isForeground = active
        }
    }

    func noteUserQualityOverride() {
        userLockedQuality = true
        sessionStepDown = nil
        didAutoStepThisSession = true
    }

    /// If sim Hz stays under ~25, drop quality one step once this session.
    func noteSlowSim() {
        guard !userLockedQuality, !didAutoStepThisSession else { return }
        let current = AppSettings.shared.quality
        let next = current.steppedDown
        guard next != current else { return }
        didAutoStepThisSession = true
        sessionStepDown = next
        objectWillChange.send()
        ToastCenter.shared.show(L10n.t("perf.slowSim"))
    }

    func effectiveQuality(user: SimQuality) -> SimQuality {
        var q = user
        if shouldThrottle { q = q.steppedDown }
        if let step = sessionStepDown, step < q { q = step }
        return q
    }

    /// Off by default on iPhone Low. On if the user picks Med/High and thermal is nominal.
    /// Thermal / Low Power always disables self-collision.
    func selfCollisionEnabled(userQuality: SimQuality) -> Bool {
        if shouldThrottle { return false }
        let q = effectiveQuality(user: userQuality)
        if isPhone && q == .low { return false }
        return q == .med || q == .high
    }

    func cappedWind(_ wind: SIMD3<Float>) -> SIMD3<Float> {
        guard shouldThrottle else { return wind }
        let cap: Float = 4
        let len = simd_length(wind)
        if len > cap { return (wind / len) * cap }
        return wind
    }

    private func startObserving() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalOrPowerChange()
        })
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalOrPowerChange()
        })
    }

    private func handleThermalOrPowerChange() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
        if shouldThrottle && !didToastCooling {
            didToastCooling = true
            ToastCenter.shared.show(L10n.t("perf.cooling"))
        }
    }
}

extension SimQuality: Comparable {
    var rank: Int {
        switch self {
        case .low: return 0
        case .med: return 1
        case .high: return 2
        }
    }

    var steppedDown: SimQuality {
        switch self {
        case .high: return .med
        case .med: return .low
        case .low: return .low
        }
    }

    static func < (lhs: SimQuality, rhs: SimQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}
