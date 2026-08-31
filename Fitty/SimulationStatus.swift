import Foundation
import Combine

/// Published HUD state. Updated from the main/render thread after a simulation step.
final class SimulationStatus: ObservableObject {
    enum Mode: String {
        case starting = "Starting"
        case bodyTracking = "Body tracking"
        case unsupported = "Body tracking unsupported"
        case simulator = "Simulator debug"
    }

    @Published var mode: Mode = .starting
    @Published var trackingState: String = "—"
    @Published var simHz: Double = 0
    @Published var particleCount: Int = 0
    @Published var bodyPresent: Bool = false
    @Published var detail: String = ""
    @Published var qualityLabel: String = "24×32"
}
