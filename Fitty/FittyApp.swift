import SwiftUI

@main
struct FittyApp: App {
    @StateObject private var store = GarmentStore()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var auth = AuthStore.shared
    @StateObject private var device = DeviceProfile.shared
    @State private var path: [FittyRoute] = []
    @Environment(\scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(auth)
                .environmentObject(device)
                .tint(FittyTheme.ink)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    device.setForeground(phase == .active)
                }
                .onChange(of: auth.sessionEmail) { _, email in
                    if email == nil { path = [] }
                }
                .onAppear {
                    device.setForeground(true)
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        ZStack {
            if auth.sessionEmail == nil {
                AuthView()
            } else if !settings.onboardingDone {
                OnboardingView { }
            } else {
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
            }
            ToastOverlay()
                .zIndex(3)
        }
    }
}
