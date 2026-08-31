import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: GarmentStore
    @EnvironmentObject var settings: AppSettings
    @Binding var path: [FittyRoute]

    private var wardrobeEmpty: Bool { store.garments.isEmpty }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                FittyTheme.canvas.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("app.name"))
                            .font(.system(size: 44, weight: .bold, design: .default))
                            .foregroundStyle(FittyTheme.ink)
                        Text(L10n.t("home.tagline"))
                            .font(.system(.body, design: .default))
                            .foregroundStyle(FittyTheme.mutedInk)
                            .dynamicTypeSize(.xSmall ... .accessibility3)
                    }
                    .padding(.top, 24)

                    if let garment = store.selected, let thumb = store.selectedFrontImage {
                        HStack(alignment: .center, spacing: 14) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .background(FittyTheme.canvas)
                                    .clipped()
                                    .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                                Text(garment.hasBack ? L10n.t("wardrobe.frontBack") : L10n.t("wardrobe.front"))
                                    .font(.system(.caption2, design: .default).weight(.semibold))
                                    .foregroundStyle(FittyTheme.ink)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(FittyTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(garment.name)
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundStyle(FittyTheme.ink)
                                    .lineLimit(2)
                                Text(garment.isolationSucceeded ? L10n.t("home.lifted") : L10n.t("home.fullFrame"))
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(FittyTheme.mutedInk)
                                Text(L10n.t(garment.kind.locKey))
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(FittyTheme.mutedInk)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(garment.name), \(L10n.t(garment.kind.locKey))")
                    }

                    Spacer(minLength: 12)

                    VStack(spacing: 12) {
                        Button(L10n.t("home.scan")) { path.append(.scan(rescanID: nil)) }
                            .buttonStyle(BoxyButtonStyle(kind: .primary))
                            .accessibilityLabel(L10n.t("a11y.scan"))

                        VStack(alignment: .leading, spacing: 6) {
                            Button(L10n.t("home.tryOn")) {
                                guard !wardrobeEmpty else { return }
                                path.append(.tryOn)
                            }
                            .buttonStyle(BoxyButtonStyle(kind: .secondary))
                            .disabled(wardrobeEmpty)
                            .opacity(wardrobeEmpty ? 0.4 : 1)
                            .accessibilityLabel(wardrobeEmpty ? L10n.t("a11y.tryOnEmpty") : L10n.t("a11y.tryOn"))
                            .accessibilityHint(wardrobeEmpty ? L10n.t("home.tryOnEmpty") : "")

                            if wardrobeEmpty {
                                Text(L10n.t("home.tryOnEmpty"))
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(FittyTheme.mutedInk)
                                    .dynamicTypeSize(.xSmall ... .accessibility3)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(L10n.t("home.wardrobe")) { path.append(.wardrobe) }
                                .buttonStyle(BoxyButtonStyle(kind: .ghost, compact: true))
                                .accessibilityLabel(L10n.t("a11y.wardrobe"))
                            Button(L10n.t("home.settings")) { path.append(.settings) }
                                .buttonStyle(BoxyButtonStyle(kind: .ghost, compact: true))
                                .accessibilityLabel(L10n.t("a11y.settings"))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .statusBarHidden(false)
    }
}
