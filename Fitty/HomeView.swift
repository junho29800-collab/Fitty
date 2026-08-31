import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: GarmentStore
    @Binding var path: [FittyRoute]

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fitty")
                        .font(.system(size: 44, weight: .bold, design: .default))
                        .foregroundStyle(FittyTheme.ink)
                    Text("Scan a garment. See it on you.")
                        .font(.system(.body, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                }
                .padding(.top, 24)

                if let garment = store.selected, let thumb = store.selectedFrontImage {
                    HStack(alignment: .center, spacing: 14) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .background(FittyTheme.canvas)
                            .clipped()
                            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last scan")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundStyle(FittyTheme.ink)
                            Text(garment.isolationSucceeded ? "Subject lifted" : "Full frame (no lift)")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(FittyTheme.mutedInk)
                        }
                        Spacer()
                    }
                }

                VStack(spacing: 12) {
                    Button("Scan clothing") {
                        path.append(.scan)
                    }
                    .buttonStyle(BoxyButtonStyle(kind: .primary))

                    Button(store.selected == nil ? "Try on (no scan yet)" : "Try on") {
                        path.append(.tryOn)
                    }
                    .buttonStyle(BoxyButtonStyle(kind: .secondary))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
