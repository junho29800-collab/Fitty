import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    var onFinished: () -> Void
    @State private var page = 0
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(L10n.t("onboard.skip")) { finish() }
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.ink)
                        .accessibilityLabel(L10n.t("onboard.skip"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TabView(selection: $page) {
                    pageView(title: L10n.t("onboard.p1.title"), body: L10n.t("onboard.p1.body"), mark: "1").tag(0)
                    pageView(title: L10n.t("onboard.p2.title"), body: L10n.t("onboard.p2.body"), mark: "2").tag(1)
                    pageView(title: L10n.t("onboard.p3.title"), body: L10n.t("onboard.p3.body"), mark: "3").tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut, value: page)

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(i == page ? FittyTheme.accent : FittyTheme.ink.opacity(0.2))
                            .frame(width: 18, height: 6)
                            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: 1))
                    }
                }

                Button(page == 2 ? L10n.t("onboard.start") : L10n.t("onboard.next")) {
                    if page == 2 { finish() } else { page += 1 }
                }
                .buttonStyle(BoxyButtonStyle(kind: .primary))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityLabel(page == 2 ? L10n.t("onboard.start") : L10n.t("onboard.next"))
            }
        }
        .preferredColorScheme(.light)
    }

    private func pageView(title: String, body: String, mark: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Rectangle().fill(FittyTheme.accent.opacity(0.35))
                Text(mark)
                    .font(.system(size: 64, weight: .bold, design: .default))
                    .foregroundStyle(FittyTheme.ink)
            }
            .frame(height: 180)
            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            Text(title)
                .font(.system(.title, design: .default).weight(.bold))
                .foregroundStyle(FittyTheme.ink)
                .dynamicTypeSize(.xSmall ... .accessibility3)
            Text(body)
                .font(.system(.body, design: .default))
                .foregroundStyle(FittyTheme.ink)
                .dynamicTypeSize(.xSmall ... .accessibility3)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func finish() {
        settings.onboardingDone = true
        onFinished()
    }
}
