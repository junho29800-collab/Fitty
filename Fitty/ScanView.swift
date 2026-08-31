import SwiftUI
import UIKit

struct ScanView: View {
    @EnvironmentObject var store: GarmentStore
    @Binding var path: [FittyRoute]

    private enum Stage {
        case capture
        case processing
        case confirm
    }

    @State private var stage: Stage = .capture
    @State private var shutterToken = 0
    @State private var cameraAvailable = false
    @State private var showPicker = false
    @State private var preview: UIImage?
    @State private var isolationSucceeded = false
    @State private var aspectRatio: CGFloat = 1
    @State private var processingNote = "Isolating garment…"

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
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
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
    }

    private var captureBody: some View {
        VStack(spacing: 16) {
            Text("Lay the garment flat, fill the frame, front side up.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(FittyTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ZStack {
                CameraViewfinder(
                    shutterToken: shutterToken,
                    onCapture: { beginIsolation($0) },
                    onAvailability: { cameraAvailable = $0 }
                )
                .clipShape(BoxyShape())

                if !cameraAvailable {
                    FittyTheme.ink.opacity(0.12)
                    VStack(spacing: 8) {
                        Text("Camera unavailable")
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(FittyTheme.ink)
                        Text("Simulator and some hardware have no rear camera. Use Choose photo.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(FittyTheme.mutedInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }

                Rectangle()
                    .stroke(FittyTheme.accent, lineWidth: 2)
                    .padding(28)
                    .allowsHitTesting(false)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button("Choose photo") { showPicker = true }
                    .buttonStyle(BoxyButtonStyle(kind: .secondary))
                Button("Shutter") { shutterToken += 1 }
                    .buttonStyle(BoxyButtonStyle(kind: .primary))
                    .disabled(!cameraAvailable)
                    .opacity(cameraAvailable ? 1 : 0.45)
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
            Text("Vision subject lift runs off the main thread.")
                .font(.system(.caption, design: .default))
                .foregroundStyle(FittyTheme.mutedInk)
            Spacer()
        }
    }

    private var confirmBody: some View {
        VStack(spacing: 16) {
            Text(isolationSucceeded
                 ? "Isolated garment. Use this, or retake."
                 : "Couldn’t lift the subject — using the full frame.")
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

            HStack(spacing: 10) {
                Button("Retake") {
                    preview = nil
                    stage = .capture
                }
                .buttonStyle(BoxyButtonStyle(kind: .secondary))
                Button("Use this") { commit() }
                    .buttonStyle(BoxyButtonStyle(kind: .primary))
                    .disabled(preview == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func beginIsolation(_ image: UIImage) {
        stage = .processing
        processingNote = "Isolating garment…"
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

    private func commit() {
        guard let preview else { return }
        _ = store.save(front: preview, isolationSucceeded: isolationSucceeded, aspectRatio: aspectRatio)
        path = [.tryOn]
    }
}
