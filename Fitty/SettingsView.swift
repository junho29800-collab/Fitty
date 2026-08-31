import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var device: DeviceProfile

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    qualityPanel
                    togglesPanel
                    prefsPanel
                    heightPanel
                    resetPanel
                    Text(L10n.t("settings.version") + " " + settings.appVersion)
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .dynamicTypeSize(.xSmall ... .accessibility3)
        }
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
        .preferredColorScheme(.light)
    }

    private var qualityPanel: some View {
        BoxyPanel {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(L10n.t("settings.iphonePerf"))
                labeledChips(
                    title: L10n.t("settings.quality"),
                    items: Array(SimQuality.allCases),
                    selection: $settings.quality,
                    label: { L10n.t($0.locKey) }
                )
                .onChange(of: settings.quality) { _, _ in
                    device.noteUserQualityOverride()
                }
                Text(L10n.t("settings.qualityHint"))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.mutedInk)
                Text(L10n.t("settings.qualityLive") + ": " + L10n.t(device.effectiveQuality(user: settings.quality).locKey))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.ink)
                Text(L10n.t("settings.thermal") + ": " + L10n.t(device.thermalLabelKey))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.ink)
                if device.isLowPower {
                    Text(L10n.t("settings.lowPower"))
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.ink)
                }
                Text(L10n.t("settings.iphonePerfBody"))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.mutedInk)
            }
        }
    }

    private var togglesPanel: some View {
        BoxyPanel {
            VStack(alignment: .leading, spacing: 10) {
                BoxySwitch(title: L10n.t("settings.haptics"), isOn: $settings.hapticsEnabled)
                BoxySwitch(title: L10n.t("settings.countdown"), isOn: $settings.scanCountdown)
                BoxySwitch(title: L10n.t("settings.debug"), isOn: $settings.debugOverlay)
            }
        }
    }

    private var prefsPanel: some View {
        BoxyPanel {
            VStack(alignment: .leading, spacing: 14) {
                labeledChips(
                    title: L10n.t("settings.units"),
                    items: Array(AppUnits.allCases),
                    selection: $settings.units,
                    label: { L10n.t($0.locKey) }
                )
                labeledChips(
                    title: L10n.t("settings.language"),
                    items: Array(AppLanguage.allCases),
                    selection: $settings.language,
                    label: { L10n.t($0.locKey) }
                )
                labeledChips(
                    title: L10n.t("settings.fabric"),
                    items: Array(FabricPreset.allCases),
                    selection: $settings.fabricDefault,
                    label: { L10n.t($0.locKey) }
                )
                .onChange(of: settings.fabricDefault) { _, v in
                    settings.lastFabric = v
                }
            }
        }
    }

    private var heightPanel: some View {
        BoxyPanel {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(L10n.t("settings.height"))
                HStack(spacing: 10) {
                    Button("−") {
                        settings.heightCm = max(150, settings.heightCm - 1)
                    }
                    .buttonStyle(.plain)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .foregroundStyle(FittyTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(FittyTheme.canvas)
                    .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                    .accessibilityLabel("−")
                    .accessibilityHint(L10n.t("settings.height"))

                    Text(heightShown)
                        .font(.system(.body, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.ink)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(L10n.t("settings.height"))
                        .accessibilityValue(heightShown)

                    Button("+") {
                        settings.heightCm = min(200, settings.heightCm + 1)
                    }
                    .buttonStyle(.plain)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .foregroundStyle(FittyTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(FittyTheme.canvas)
                    .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                    .accessibilityLabel("+")
                    .accessibilityHint(L10n.t("settings.height"))
                }
                Text(L10n.t("settings.heightHint"))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.mutedInk)
            }
        }
    }

    private var resetPanel: some View {
        BoxyPanel {
            Button(L10n.t("settings.resetOnboard")) {
                settings.resetOnboarding()
            }
            .buttonStyle(BoxyButtonStyle(kind: .secondary))
            .accessibilityLabel(L10n.t("settings.resetOnboard"))
        }
    }

    private var heightShown: String {
        if settings.units == .meters {
            return String(format: "%.2f m", Double(settings.heightCm) / 100.0)
        }
        return String(settings.heightCm) + " cm"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .default).weight(.semibold))
            .foregroundStyle(FittyTheme.mutedInk)
    }

    private func labeledChips<T: Hashable & Identifiable>(
        title: String,
        items: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button(label(item)) { selection.wrappedValue = item }
                        .buttonStyle(.plain)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(FittyTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(selection.wrappedValue == item ? FittyTheme.accent : FittyTheme.canvas)
                        .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                        .accessibilityLabel(label(item))
                        .accessibilityAddTraits(selection.wrappedValue == item ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
