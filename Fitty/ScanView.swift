import AVFoundation
import SwiftUI
import UIKit

struct ScanView: View {
    @EnvironmentObject var store: GarmentStore
    @EnvironmentObject var settings: AppSettings
    @Binding var path: [FittyRoute]
    var rescanID: UUID?

    private enum Stage {
        case capture
        case processing
        case confirm
        case denied
    }

    private enum Face {
        case front, back
    }

    @State private var stage: Stage = .capture
    @State private var face: Face = .front
    @State private var shutterToken = 0
    @State private var cameraAvailable = false
    @State private var showPicker = false
    @State private var preview: UIImage?
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var isolationSucceeded = false
    @State private var aspectRatio: CGFloat = 1
    @State private var processingNote = ""
    @State private var kind: GarmentKind = .tee
    @State private var countdown: Int? = nil
    @State private var flash = false

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            switch stage {
            case .capture:
                captureBody
            case .processing:
                processingBody
            case .confirm:
                confirmBody
            case .denied:
                deniedBody
            }
            if flash {
                Color.white.opacity(0.55).ignoresSafeArea().allowsHitTesting(false)
            }
            ToastOverlay()
        }
        .navigationTitle(face == .front ? L10n.t("scan.frontStage") : L10n.t("scan.backStage"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(
                onPick: { image in
                    showPicker = false
                    beginIsolation(image)
                },
                onCancel: { showPicker = false }
            )
            .ignoresSafeArea()
        }
        .onAppear {
            processingNote = L10n.t("scan.isolating")
            checkCameraAuth()
            if let existing = rescanID, let g = store.garments.first(where: { $0.id == existing }) {
                kind = g.kind
            }
        }
    }

    private var captureBody: some View {
        VStack(spacing: 16) {
            Text(face == .front ? L10n.t("scan.frontHint") : L10n.t("scan.backHint"))
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(FittyTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .dynamicTypeSize(.xSmall ... .accessibility2)

            ZStack {
                CameraViewfinder(
                    shutterToken: shutterToken,
                    onCapture: { beginIsolation($0) },
                    onAvailability: { cameraAvailable = $0 },
                    onDenied: { stage = .denied }
                )
                .clipShape(BoxyShape())

                if !cameraAvailable {
                    FittyTheme.ink.opacity(0.12)
                    VStack(spacing: 8) {
                        Text(L10n.t("scan.cameraUnavailable"))
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(FittyTheme.ink)
                        Text(L10n.t("scan.cameraUnavailableBody"))
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(FittyTheme.mutedInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }

                ReticleTicks()

                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 72, weight: .bold, design: .default))
                        .foregroundStyle(FittyTheme.accent)
                        .shadow(color: FittyTheme.ink.opacity(0.4), radius: 0, x: 2, y: 2)
                        .accessibilityLabel("\(countdown)")
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button(L10n.t("scan.choose")) { showPicker = true }
                    .buttonStyle(BoxyButtonStyle(kind: .secondary))
                    .accessibilityLabel(L10n.t("a11y.choose"))
                Button(L10n.t("scan.shutter")) { fireShutter() }
                    .buttonStyle(BoxyButtonStyle(kind: .primary))
                    .disabled(!cameraAvailable || countdown != nil)
                    .opacity(cameraAvailable ? 1 : 0.45)
                    .accessibilityLabel(L10n.t("a11y.shutter"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var processingBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(processingNote)
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.ink)
            Text(L10n.t("scan.isolatingNote"))
                .font(.system(.caption, design: .default))
                .foregroundStyle(FittyTheme.mutedInk)
            Spacer()
        }
    }

    private var confirmBody: some View {
        VStack(spacing: 12) {
            Text(isolationSucceeded ? L10n.t("scan.isolated") : L10n.t("scan.fullFrame"))
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(FittyTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ZStack {
                FittyTheme.canvas
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .padding(.horizontal, 20)

            if face == .front {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("scan.kind"))
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.mutedInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GarmentKind.allCases) { k in
                                Button(L10n.t(k.locKey)) { kind = k }
                                    .font(.system(.caption, design: .default).weight(.semibold))
                                    .foregroundStyle(FittyTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(kind == k ? FittyTheme.accent : FittyTheme.canvas)
                                    .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                                    .accessibilityLabel(L10n.t(k.locKey))
                                    .accessibilityAddTraits(kind == k ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 10) {
                Button(L10n.t("scan.retake")) {
                    preview = nil
                    stage = .capture
                }
                .buttonStyle(BoxyButtonStyle(kind: .secondary, compact: true))
                if face == .front {
                    Button(L10n.t("scan.addBack")) { keepFrontThenBack() }
                        .buttonStyle(BoxyButtonStyle(kind: .ghost, compact: true))
                        .disabled(preview == nil)
                    Button(L10n.t("scan.skipBack")) { commit(frontOnly: true) }
                        .buttonStyle(BoxyButtonStyle(kind: .primary, compact: true))
                        .disabled(preview == nil)
                } else {
                    Button(L10n.t("scan.useThis")) { commit(frontOnly: false) }
                        .buttonStyle(BoxyButtonStyle(kind: .primary, compact: true))
                        .disabled(preview == nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var deniedBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("scan.cameraDeniedTitle"))
                .font(.system(.title2, design: .default).weight(.bold))
                .foregroundStyle(FittyTheme.ink)
            Text(L10n.t("scan.cameraDeniedBody"))
                .font(.system(.body, design: .default))
                .foregroundStyle(FittyTheme.ink)
            Button(L10n.t("scan.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(BoxyButtonStyle(kind: .primary))
            .accessibilityLabel(L10n.t("scan.openSettings"))
            Button(L10n.t("scan.choose")) { showPicker = true }
                .buttonStyle(BoxyButtonStyle(kind: .secondary))
            Spacer()
        }
        .padding(24)
        .dynamicTypeSize(.xSmall ... .accessibility3)
    }

    private func checkCameraAuth() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            stage = .denied
        default:
            break
        }
    }

    private func fireShutter() {
        FittyHaptics.shutter()
        let useCountdown = settings.scanCountdown && !reduceMotion && cameraAvailable
        if useCountdown {
            countdown = 3
            tickCountdown()
        } else {
            pulseFlash()
            shutterToken += 1
        }
    }

    private func tickCountdown() {
        guard let n = countdown else { return }
        if n <= 1 {
            countdown = nil
            pulseFlash()
            shutterToken += 1
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            countdown = n - 1
            tickCountdown()
        }
    }

    private func pulseFlash() {
        if reduceMotion { return }
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
    }

    private func beginIsolation(_ image: UIImage) {
        stage = .processing
        processingNote = L10n.t("scan.isolating")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = GarmentIsolator.isolate(image)
            DispatchQueue.main.async {
                preview = outcome.image
                isolationSucceeded = outcome.isolationSucceeded
                aspectRatio = outcome.aspectRatio
                stage = .confirm
            }
        }
    }

    private func keepFrontThenBack() {
        guard let preview else { return }
        frontImage = preview
        self.preview = nil
        face = .back
        stage = .capture
    }

    private func commit(frontOnly: Bool) {
        guard let preview else { return }
        FittyHaptics.confirm()
        let front = frontOnly ? preview : (frontImage ?? preview)
        let back = frontOnly ? nil : preview
        let saved: Garment?
        if let rescanID {
            saved = store.updatePhotos(id: rescanID,
                                       front: front,
                                       back: back,
                                       isolationSucceeded: isolationSucceeded,
                                       aspectRatio: aspectRatio,
                                       kind: kind)
            if saved != nil { ToastCenter.shared.show(L10n.t("scan.updated")) }
        } else {
            saved = store.save(front: front,
                               back: back,
                               isolationSucceeded: isolationSucceeded,
                               aspectRatio: aspectRatio,
                               kind: kind)
            if saved != nil { ToastCenter.shared.show(L10n.t("scan.saved")) }
        }
        if saved == nil { return }
        path = [.tryOn]
    }
}
