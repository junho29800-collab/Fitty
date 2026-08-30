import SwiftUI

struct ContentView: View {
    @StateObject private var status = SimulationStatus()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARViewController(status: status)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                Text("Fitty")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                overlayRow("Tracking", status.mode.rawValue)
                overlayRow("AR camera", status.trackingState)
                overlayRow("Body", status.bodyPresent ? "locked" : "waiting")
                overlayRow("Sim", String(format: "%.0f Hz · %d particles", status.simHz, status.particleCount))
                if !status.detail.isEmpty {
                    Text(status.detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(16)

            if status.mode == .unsupported || status.mode == .simulator {
                VStack {
                    Spacer()
                    Text(status.mode == .simulator
                         ? "Simulator: T-pose capsule rig (body tracking requires a device)"
                         : "Body tracking unsupported — debug T-pose rig is running")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func overlayRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView()
}
