import SwiftUI
import UIKit

/// Try-on: AR body tracking + PBD cloth, cream boxy HUD.
struct ContentView: View {
    @EnvironmentObject var store: GarmentStore
    @EnvironmentObject var settings: AppSettings
    @Binding var path: [FittyRoute]
    @StateObject private var status = SimulationStatus()
    @StateObject private var recorder = ClipRecorder.shared
    @State private var snapshotToken = 0
    @State private var showFit = false
    @State private var compareIndex = 0
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                ARViewController(
                    status: status,
                    settings: settings,
                    garmentImage: store.selectedFrontImage,
                    garmentBack: store.selectedBackImage,
                    garmentAspect: Float(store.selected?.aspectRatio ?? 0),
                    garmentKind: store.selected?.kind ?? .tee,
                    snapshotToken: snapshotToken,
                    onSnapshot: handleSnapshot
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topHUD
                        .padding(.top, geo.safeAreaInsets.top > 0 ? 4 : 12)
                    Spacer()
                    if status.mode == .unsupported || status.mode == .simulator {
                        Text(status.mode == .simulator ? L10n.t("tryOn.sim") : L10n.t("tryOn.unsupported"))
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(FittyTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(FittyTheme.panel)
                            .overlay(BoxyShape().stroke(FittyTheme.accent, lineWidth: FittyTheme.stroke))
                            .padding(.horizontal, 16)
                    }
                    bottomHUD(landscape: landscape)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 12))
                }
            }
        }
        .navigationTitle(L10n.t("tryOn.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas.opacity(0.92), for: .navigationBar)
        .tint(FittyTheme.ink)
        .statusBarHidden(true)
        .sheet(isPresented: $showShare) {
            ActivityShare(items: shareItems)
        }
        .overlay(ToastOverlay())
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.debugOverlay {
                Text(L10n.t("app.name"))
                    .font(.system(.headline, design: .default).weight(.bold))
                    .foregroundStyle(FittyTheme.ink)
                overlayRow("Tracking", status.mode.rawValue)
                overlayRow("AR camera", status.trackingState)
                overlayRow("Body", status.bodyPresent ? "locked" : "waiting")
                overlayRow("Sim", String(format: "%.0f Hz · %d · %@", status.simHz, status.particleCount, status.qualityLabel))
                overlayRow("Cloth", store.selectedFrontImage == nil ? L10n.t("tryOn.woven") : L10n.t("tryOn.scanned"))
                if !status.detail.isEmpty {
                    Text(status.detail)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            } else {
                HStack {
                    Text(store.selected?.name ?? L10n.t("app.name"))
                        .font(.system(.subheadline, design: .default).weight(.bold))
                        .foregroundStyle(FittyTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(L10n.t(settings.lastFabric.locKey))
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.ink)
                }
            }
        }
        .padding(12)
        .background(FittyTheme.panel)
        .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func bottomHUD(landscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fabricRow
            sizeRow
            if showFit {
                fitSliders
                windRow
            }
            HStack(spacing: 8) {
                Button(L10n.t("tryOn.fit")) { showFit.toggle() }
                    .buttonStyle(BoxyButtonStyle(kind: .ghost, compact: true))
                    .accessibilityLabel(L10n.t("tryOn.fit"))
                Button(L10n.t("tryOn.snapshot")) { takeSnapshot() }
                    .buttonStyle(BoxyButtonStyle(kind: .secondary, compact: true))
                    .accessibilityLabel(L10n.t("a11y.snapshot"))
                Button(recorder.isRecording ? L10n.t("tryOn.recording") : L10n.t("tryOn.record")) {
                    recordClip()
                }
                .buttonStyle(BoxyButtonStyle(kind: recorder.isRecording ? .primary : .secondary, compact: true))
                .accessibilityLabel(L10n.t("a11y.record"))
            }
            HStack(spacing: 8) {
                Button(L10n.t("tryOn.compare")) { swapAB() }
                    .buttonStyle(BoxyButtonStyle(kind: .ghost, compact: true))
                    .disabled(store.garments.count < 2)
                    .opacity(store.garments.count < 2 ? 0.45 : 1)
                    .accessibilityLabel(L10n.t("a11y.compare"))
                Button(L10n.t("tryOn.rescan")) {
                    path = [.scan(rescanID: store.selectedID)]
                }
                .buttonStyle(BoxyButtonStyle(kind: .secondary, compact: true))
                .accessibilityLabel(L10n.t("tryOn.rescan"))
                Button(L10n.t("tryOn.newGarment")) {
                    path = [.scan(rescanID: nil)]
                }
                .buttonStyle(BoxyButtonStyle(kind: .primary, compact: true))
                .accessibilityLabel(L10n.t("tryOn.newGarment"))
            }
        }
        .padding(10)
        .background(FittyTheme.panel)
        .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var fabricRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("tryOn.fabric"))
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.mutedInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FabricPreset.allCases) { f in
                        Button(L10n.t(f.locKey)) { settings.lastFabric = f }
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(FittyTheme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(settings.lastFabric == f ? FittyTheme.accent : FittyTheme.canvas)
                            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                            .accessibilityLabel(L10n.t(f.locKey))
                            .accessibilityAddTraits(settings.lastFabric == f ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("tryOn.size"))
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.mutedInk)
            HStack(spacing: 0) {
                ForEach(GarmentSize.allCases) { s in
                    Button(s.label) {
                        settings.lastSize = s
                    }
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(FittyTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(settings.lastSize == s ? FittyTheme.accent : FittyTheme.canvas)
                    .accessibilityLabel(s.label)
                    .accessibilityAddTraits(settings.lastSize == s ? .isSelected : [])
                }
            }
            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
        }
    }

    private var fitSliders: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeledSlider(L10n.t("tryOn.length"), value: $settings.fitLength, range: 0.7...1.5)
            labeledSlider(L10n.t("tryOn.tightness"), value: $settings.fitTightness, range: 0.55...1.6)
            labeledSlider(L10n.t("tryOn.drape"), value: $settings.fitDrape, range: 0.15...2.0)
        }
    }

    private var windRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeledSlider(L10n.t("tryOn.wind"), value: $settings.windStrength, range: 0...12)
            labeledSlider(L10n.t("tryOn.windDir"), value: $settings.windAngle, range: 0...(2 * Float.pi))
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack {
            Text(title)
                .font(.system(.caption, design: .default))
                .foregroundStyle(FittyTheme.ink)
                .frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
                .tint(FittyTheme.accent)
                .accessibilityLabel(title)
        }
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

    private func takeSnapshot() {
        FittyHaptics.snapshot()
        snapshotToken += 1
    }

    private func handleSnapshot(_ image: UIImage?) {
        guard let image else {
            ToastCenter.shared.show(L10n.t("tryOn.snapshotFailed"))
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "fitty-\(Int(Date().timeIntervalSince1970)).png"
        let url = dir.appendingPathComponent(name)
        do {
            guard let data = ImageIOSupport.compressedPNG(image) else { throw NSError(domain: "Fitty", code: 2) }
            try data.write(to: url, options: .atomic)
            shareItems = [url]
            showShare = true
            ToastCenter.shared.show(L10n.t("tryOn.snapshotSaved"))
        } catch {
            ToastCenter.shared.show(L10n.t("scan.saveFailed"))
        }
    }

    private func recordClip() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            ToastCenter.shared.show(L10n.t("tryOn.recordFailed"))
            return
        }
        var presenter = root
        while let p = presenter.presentedViewController { presenter = p }
        recorder.toggle(from: presenter)
    }

    private func swapAB() {
        let list = store.sortedGarments(by: settings.wardrobeSort)
        guard list.count >= 2 else {
            ToastCenter.shared.show(L10n.t("tryOn.compareNeedTwo"))
            return
        }
        compareIndex = (compareIndex + 1) % list.count
        store.select(list[compareIndex].id)
    }
}

struct ActivityShare: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
