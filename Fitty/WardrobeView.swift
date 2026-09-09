import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject var store: GarmentStore
    @EnvironmentObject var settings: AppSettings
    @Binding var path: [FittyRoute]
    @State private var pendingDelete: Garment?
    @State private var renameTarget: Garment?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                sortBar
                if store.garments.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .navigationTitle(L10n.t("wardrobe.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
        .preferredColorScheme(.light)
        .alert(L10n.t("wardrobe.delete"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L10n.t("wardrobe.delete"), role: .destructive) {
                if let g = pendingDelete { store.delete(g.id) }
                pendingDelete = nil
            }
            Button(L10n.t("cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L10n.t("wardrobe.deleteConfirm"))
        }
        .alert(L10n.t("wardrobe.rename"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(L10n.t("wardrobe.rename"), text: $renameText)
            Button(L10n.t("save")) {
                if let g = renameTarget { store.rename(g.id, to: renameText) }
                renameTarget = nil
            }
            Button(L10n.t("cancel"), role: .cancel) { renameTarget = nil }
        }
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            sortChip(.newest, L10n.t("wardrobe.sortNewest"))
            sortChip(.name, L10n.t("wardrobe.sortName"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sortChip(_ sort: WardrobeSort, _ label: String) -> some View {
        Button(label) { settings.wardrobeSort = sort }
            .font(.system(.caption, design: .default).weight(.semibold))
            .foregroundStyle(FittyTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(settings.wardrobeSort == sort ? FittyTheme.accent : FittyTheme.canvas)
            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .accessibilityLabel(label)
            .accessibilityAddTraits(settings.wardrobeSort == sort ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Rectangle().fill(FittyTheme.accent.opacity(0.25))
                VStack(spacing: 6) {
                    Rectangle()
                        .stroke(FittyTheme.ink, lineWidth: 2)
                        .frame(width: 54, height: 64)
                    Text("F")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(FittyTheme.accent)
                }
            }
            .frame(width: 160, height: 160)
            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            Text(L10n.t("wardrobe.emptyTitle"))
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundStyle(FittyTheme.ink)
                .dynamicTypeSize(.xSmall ... .accessibility3)
            Text(L10n.t("wardrobe.emptyBody"))
                .font(.system(.body, design: .default))
                .foregroundStyle(FittyTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .dynamicTypeSize(.xSmall ... .accessibility3)
            Button(L10n.t("home.scan")) { path.append(.scan(rescanID: nil)) }
                .buttonStyle(BoxyButtonStyle(kind: .primary))
                .padding(.horizontal, 40)
                .accessibilityLabel(L10n.t("a11y.scan"))
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.sortedGarments(by: settings.wardrobeSort)) { g in
                    row(g)
                }
            }
            .padding(16)
        }
    }

    private func row(_ g: Garment) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let img = g.loadFront() {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    FittyTheme.accent.opacity(0.3)
                }
                Text(g.hasBack ? L10n.t("wardrobe.frontBack") : L10n.t("wardrobe.front"))
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(FittyTheme.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(FittyTheme.accent)
            }
            .frame(width: 72, height: 72)
            .clipped()
            .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))

            VStack(alignment: .leading, spacing: 3) {
                Text(g.name)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(FittyTheme.ink)
                    .lineLimit(2)
                Text("\(L10n.t(g.kind.locKey)) · \(shortDate(g.created))")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(FittyTheme.mutedInk)
                if !g.notes.isEmpty {
                    Text(g.notes)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(FittyTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button(L10n.t("wardrobe.tryOn")) {
                    store.select(g.id)
                    path.append(.tryOn)
                }
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(FittyTheme.accent)
                .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: 1))
                .accessibilityLabel(L10n.t("a11y.tryOn"))
            }
        }
        .padding(8)
        .background(store.selectedID == g.id ? FittyTheme.accent.opacity(0.18) : FittyTheme.canvas)
        .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
        .onTapGesture { store.select(g.id) }
        .contextMenu {
            Button(L10n.t("wardrobe.edit")) { path.append(.editor(g.id)) }
            Button(L10n.t("wardrobe.rename")) {
                renameText = g.name
                renameTarget = g
            }
            Button(L10n.t("wardrobe.delete"), role: .destructive) { pendingDelete = g }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(g.name), \(L10n.t(g.kind.locKey))")
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}

struct GarmentEditorView: View {
    @EnvironmentObject var store: GarmentStore
    let id: UUID
    @State private var name = ""
    @State private var notes = ""
    @State private var kind: GarmentKind = .tee

    var body: some View {
        ZStack {
            FittyTheme.canvas.ignoresSafeArea()
            if let g = store.garments.first(where: { $0.id == id }) {
                Form {
                    Section(L10n.t("wardrobe.rename")) {
                        TextField(L10n.t("wardrobe.rename"), text: $name)
                    }
                    Section(L10n.t("wardrobe.kind")) {
                        Picker(L10n.t("wardrobe.kind"), selection: $kind) {
                            ForEach(GarmentKind.allCases) { k in
                                Text(L10n.t(k.locKey)).tag(k)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    Section(L10n.t("wardrobe.notes")) {
                        TextField(L10n.t("wardrobe.notes"), text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section(L10n.t("wardrobe.date")) {
                        Text(g.created.formatted(date: .long, time: .shortened))
                            .foregroundStyle(FittyTheme.ink)
                    }
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    name = g.name
                    notes = g.notes
                    kind = g.kind
                }
                .onDisappear {
                    store.rename(id, to: name)
                    store.setNotes(id, notes: notes)
                    store.setKind(id, kind: kind)
                }
            }
        }
        .navigationTitle(L10n.t("wardrobe.edit"))
        .toolbarBackground(FittyTheme.canvas, for: .navigationBar)
        .tint(FittyTheme.ink)
        .preferredColorScheme(.light)
    }
}
