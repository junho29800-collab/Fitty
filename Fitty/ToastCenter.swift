import Combine
import SwiftUI

/// Transient cream toast for errors and success. Not a banner, not a capsule.
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String = ""
    @Published var visible = false
    private var token = 0

    func show(_ text: String, seconds: Double = 2.4) {
        token += 1
        let mine = token
        message = text
        visible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.token == mine else { return }
            self.visible = false
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject var toast = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if toast.visible && !toast.message.isEmpty {
                Text(toast.message)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(FittyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 360)
                    .background(FittyTheme.canvas.opacity(0.96))
                    .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                    .padding(.bottom, 28)
                    .transition(.opacity)
                    .accessibilityLabel(toast.message)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: toast.visible)
        .allowsHitTesting(false)
    }
}
