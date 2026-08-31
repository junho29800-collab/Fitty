import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var device: DeviceProfile
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            List {
                Section {
                    if let mail = auth.sessionEmail {
                        Text("\(L10n.t(\"settings.signedIn\")) \(mail)")
                            .font(.system(.subheadline, design: .default))
                            .foregroundStyle(FittyTheme.ink)
                    }
                    Button(L10n.t("auth.logout")) {
                        auth.logOut()
                    }
                    .accessibilityLabel(L10n.t("a11y.logout"))
                } header: { Text(L10n.t("auth.logout")) }

                Section {
                    Picker(L10n.t("settings.quality"), selection: $settings.quality) {
                        ForEach(SimQuality.allCases) { q in
                            Text(L10n.t(q.locKey)).tag(q)
                        }
                    }
                    .accessibilityLabel(L10n.t("settings.quality"))
                    .onChange(of: settings.quality) { _, _ in
                        device.noteUserQualityOverride()
                    }
                    Text(L10n.t("settings.qualityHint"))
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                    Text("\(L10n.t(\"settings.qualityLive\")): \(L10n.t(device.effectiveQuality(user: settings.quality).locKey))")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.ink)
                    Text("\(L10n.t(\"settings.thermal\")): \(L10n.t(device.thermalLabelKey))")
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
                } header: { Text(L10n.t("settings.iphonePerf")) }

                Section {
                    Toggle(L10n.t("settings.haptics"), isOn: $settings.hapticsEnabled)
                        .accessibilityLabel(L10n.t("settings.haptics"))
                    Toggle(L10n.t("settings.countdown"), isOn: $settings.scanCountdown)
                        .accessibilityLabel(L10n.t("settings.countdown"))
                    Toggle(L10n.t("settings.debug"), isOn: $settings.debugOverlay)
                        .accessibilityLabel(L10n.t("settings.debug"))
                }

                Section {
                    Picker(L10n.t("settings.units"), selection: $settings.units) {
                        ForEach(AppUnits.allCases) { u in
                            Text(L10n.t(u.locKey)).tag(u)
                        }
                    }
                    .accessibilityLabel(L10n.t("settings.units"))
                    Picker(L10n.t("settings.language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { l in
                            Text(L10n.t(l.locKey)).tag(l)
                        }
                    }
                    .accessibilityLabel(L10n.t("settings.language"))
                    Picker(L10n.t("settings.fabric"), selection: $settings.fabricDefault) {
                        ForEach(FabricPreset.allCases) { f in
                            Text(L10n.t(f.locKey)).tag(f)
                        }
                    }
                    .onChange(of: settings.fabricDefault) { _, v in
                        settings.lastFabric = v
                    }
                    .accessibilityLabel(L10n.t("settings.fabric"))
                }

                Section {
                    Stepper(value: $settings.heightCm, in: 150...200, step: 1) {
                        let shown: String
                        if settings.units == .meters {
                            shown = String(format: "%.2f m", Double(settings.heightCm) / 100.0)
                        } else {
                            shown = "\(settings.heightCm) cm"
                        }
                        return Text("\(L10n.t(\"settings.height\"))  \(shown)")
                    }
                    .accessibilityLabel(L10n.t("settings.height"))
                    Text(L10n.t("settings.heightHint"))
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                } header: { Text(L10n.t("settings.height")) }

                Section {
                    Button(L10n.t("settings.resetOnboard")) {
                        settings.resetOnboarding()
                    }
                    .accessibilityLabel(L10n.t("settings.resetOnboard"))
                }

                Section {
                    Text("\(L10n.t(\"settings.version\")) \(settings.appVersion)")
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .dynamicTypeSize(.xSmall ... .accessibility3)
        }
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
        .preferredColorScheme(.light)
    }
}
