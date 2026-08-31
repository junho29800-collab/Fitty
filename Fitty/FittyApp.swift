import SwiftUI

@main
struct FittyApp: App {
    @StateObject private var store = GarmentStore()
    @StateObject private var settings = AppSettings.shared
    @State private var path: [FittyRoute] = []
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                NavigationStack(path: $path) {
                    HomeView(path: $path)
                        .navigationDestination(for: FittyRoute.self) { route in
                            switch route {
                            case .scan(let rescanID):
                                ScanView(path: $path, rescanID: rescanID)
                            case .tryOn:
                                ContentView(path: $path)
                            case .wardrobe:
                                WardrobeView(path: $path)
                            case .settings:
                                SettingsView()
                            case .editor(let id):
                                GarmentEditorView(id: id)
                            }
                        }
                }
                .environmentObject(store)
                .environmentObject(settings)
                .tint(FittyTheme.ink)
                .preferredColorScheme(.light)

                if showOnboarding {
                    OnboardingView {
                        showOnboarding = false
                    }
                    .environmentObject(settings)
                    .transition(.opacity)
                    .zIndex(2)
                }

                ToastOverlay()
                    .zIndex(3)
            }
            .onAppear {
                if !settings.onboardingDone {
                    showOnboarding = true
                }
            }
            .onChange(of: settings.onboardingDone) { _, done in
                if !done { showOnboarding = true }
            }
        }
    }
}
