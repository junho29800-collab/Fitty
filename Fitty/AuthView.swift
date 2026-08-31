import SwiftUI

/// First-launch gate. Login / Sign up before onboarding or Home.
/// Google and Apple are visible but disabled ("Coming soon") — no fake OAuth.
struct AuthView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @FocusState private var focus: Field?

    private enum Mode { case login, signup }
    private enum Field { case email, password, confirm }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                FittyTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("app.name"))
                                .font(.system(size: 44, weight: .bold, design: .default))
                                .foregroundStyle(FittyTheme.ink)
                            Text(L10n.t("auth.tagline"))
                                .font(.system(.body, design: .default))
                                .foregroundStyle(FittyTheme.mutedInk)
                                .dynamicTypeSize(.xSmall ... .accessibility3)
                        }
                        .padding(.top, 12)
                        modeSwitcher
                        emailField
                        passwordField
                        if mode == .signup { confirmField }
                        Button(mode == .login ? L10n.t("auth.submitLogin") : L10n.t("auth.submitSignup")) {
                            submit()
                        }
                        .buttonStyle(BoxyButtonStyle(kind: .primary))
                        .accessibilityLabel(mode == .login ? L10n.t("a11y.login") : L10n.t("a11y.signup"))
                        comingSoonRow
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
                    .frame(minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture { focus = nil }
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeButton(L10n.t("auth.login"), .login)
            modeButton(L10n.t("auth.signup"), .signup)
        }
        .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
    }

    private func modeButton(_ title: String, _ m: Mode) -> some View {
        Button(title) { mode = m; confirm = "" }
            .font(.system(.subheadline, design: .default).weight(.semibold))
            .foregroundStyle(FittyTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(mode == m ? FittyTheme.accent : FittyTheme.canvas)
            .accessibilityLabel(title)
            .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    private var emailField: some View {
        labeled(L10n.t("auth.email")) {
            TextField(L10n.t("auth.email"), text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
        }
    }

    private var passwordField: some View {
        labeled(L10n.t("auth.password")) {
            SecureField(L10n.t("auth.password"), text: $password)
                .textContentType(mode == .signup ? .newPassword : .password)
                .submitLabel(mode == .signup ? .next : .go)
                .focused($focus, equals: .password)
                .onSubmit { if mode == .signup { focus = .confirm } else { submit() } }
        }
    }

    private var confirmField: some View {
        labeled(L10n.t("auth.confirm")) {
            SecureField(L10n.t("auth.confirm"), text: $confirm)
                .textContentType(.newPassword)
                .submitLabel(.go)
                .focused($focus, equals: .confirm)
                .onSubmit { submit() }
        }
    }

    private func labeled<V: View>(_ title: String, @ViewBuilder field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.mutedInk)
            field()
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(FittyTheme.canvas)
                .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
                .foregroundStyle(FittyTheme.ink)
        }
    }

    private var comingSoonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            disabledProvider(L10n.t("auth.google"))
            disabledProvider(L10n.t("auth.apple"))
        }
    }

    private func disabledProvider(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.ink.opacity(0.45))
            Spacer()
            Text(L10n.t("auth.comingSoon"))
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(FittyTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FittyTheme.accent.opacity(0.55))
                .overlay(Rectangle().stroke(FittyTheme.ink, lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(FittyTheme.canvas)
        .overlay(BoxyShape().stroke(FittyTheme.ink.opacity(0.35), lineWidth: FittyTheme.stroke))
        .disabled(true)
        .accessibilityLabel(title + ", " + L10n.t("auth.comingSoon"))
    }

    private func submit() {
        focus = nil
        let err: String?
        if mode == .login {
            err = auth.logIn(email: email, password: password)
        } else {
            err = auth.signUp(email: email, password: password, confirm: confirm)
        }
        if let err { ToastCenter.shared.show(err) }
        password = ""
        confirm = ""
    }
}
