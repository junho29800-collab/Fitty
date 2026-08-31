import SwiftUI

/// Try-on: AR body tracking + PBD cloth, with a light cream boxy HUD.
struct ContentView: View {
    @EnvironmentObject var store: GarmentStore
    @Binding var path: [FittyRoute]
    @StateObject private var status = SimulationStatus()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARViewController(
                status: status,
                garmentImage: store.selectedFrontImage,
                garmentAspect: Float(store.selected?.aspectRatio ?? 0)
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                Text("Fitty")
                    .font(.system(.headline, design: .default).weight(.bold))
                    .foregroundStyle(FittyTheme.ink)
                overlayRow("Tracking", status.mode.rawValue)
                overlayRow("AR camera", status.trackingState)
                overlayRow("Body", status.bodyPresent ? "locked" : "waiting")
                overlayRow("Sim", String(format: "%.0f Hz · %d particles", status.simHz, status.particleCount))
                overlayRow("Cloth", store.selectedFrontImage == nil ? "woven default" : "scanned albedo")
                if !status.detail.isEmpty {
                    Text(status.detail)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(FittyTheme.panel)
            .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .padding(16)

            VStack {
                Spacer()
                if status.mode == .unsupported || status.mode == .simulator {
                    Text(status.mode == .simulator
                         ? "Simulator: T-pose capsule rig (body tracking requires a device)"
                         : "Body tracking unsupported — debug T-pose rig is running")
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(FittyTheme.panel)
                        .overlay(BoxyShape().stroke(FittyTheme.accent, lineWidth: FittyTheme.stroke))
                        .padding(.horizontal, 16)
                }
                Button("Rescan") { path = [.scan] }
                    .buttonStyle(BoxyButtonStyle(kind: .primary, compact: true))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Try on")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas.opacity(0.92), for: .navigationBar)
        .tint(FittyTheme.ink)
    }

    private func overlayRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key.uppercased())
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.mutedInk)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(FittyTheme.ink)
        }
    }
}

#Preview {
    ContentView(path: .constant([]))
        .environmentObject(GarmentStore())
}
