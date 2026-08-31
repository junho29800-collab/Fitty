import SwiftUI

@main
struct FittyApp: App {
    @StateObject private var store = GarmentStore()
    @State private var path: [FittyRoute] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: FittyRoute.self) { route in
                        switch route {
                        case .scan:
                            ScanView(path: $path)
                        case .tryOn:
                            ContentView(path: $path)
                        }
                    }
            }
            .environmentObject(store)
            .tint(FittyTheme.ink)
        }
    }
}
