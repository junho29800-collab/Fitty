import Combine
import CryptoKit
import Foundation
import Security

/// Local-only accounts. Email list + session email in UserDefaults; salt + SHA256 hash
/// in Keychain. Never logs passwords. Never sends them to a network.
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    private let d = UserDefaults.standard
    private let emailsKey = "fitty.auth.emails"
    private let sessionKey = "fitty.auth.session"

    /// Current session email, or nil when logged out.
    @Published private(set) var sessionEmail: String?

    private init() {
        let saved = d.string(forKey: sessionKey)
        if let saved, !saved.isEmpty, loadCred(email: saved) != nil {
            sessionEmail = saved
        } else {
            sessionEmail = nil
            d.removeObject(forKey: sessionKey)
        }
    }

    func signUp(email: String, password: String, confirm: String) -> String? {
        let mail = normalize(email)
        if !isValidEmail(mail) { return L10n.t("auth.invalidEmail") }
        if password.count < 8 { return L10n.t("auth.passwordShort") }
        if password != confirm { return L10n.t("auth.passwordMismatch") }
        if emails().contains(mail) || loadCred(email: mail) != nil {
            return L10n.t("auth.duplicate")
        }
        var salt = Data(count: 16)
        let saltStatus = salt.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, 16, buf.baseAddress!)
        }
        if saltStatus != errSecSuccess {
            salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        }
        let hash = hashPassword(password, salt: salt)
        let cred = Cred(salt: salt, hash: hash)
        guard let blob = try? JSONEncoder().encode(cred),
              KeychainBox.set(blob, account: mail) else {
            return L10n.t("auth.duplicate")
        }
        var list = emails()
        if !list.contains(mail) { list.append(mail) }
        d.set(list, forKey: emailsKey)
        setSession(mail)
        return nil
    }

    func logIn(email: String, password: String) -> String? {
        let mail = normalize(email)
        guard let cred = loadCred(email: mail) else {
            return L10n.t("auth.badCredentials")
        }
        let hash = hashPassword(password, salt: cred.salt)
        if !timingSafeEqual(hash, cred.hash) {
            return L10n.t("auth.badCredentials")
        }
        setSession(mail)
        return nil
    }

    func logOut() {
        sessionEmail = nil
        d.removeObject(forKey: sessionKey)
        ToastCenter.shared.show(L10n.t("auth.loggedOut"))
    }

    private func setSession(_ email: String) {
        sessionEmail = email
        d.set(email, forKey: sessionKey)
    }

    private func emails() -> [String] {
        d.stringArray(forKey: emailsKey) ?? []
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    /// SHA256(password + per-user salt). Password bytes are not retained.
    private func hashPassword(_ password: String, salt: Data) -> Data {
        var bytes = Data(password.utf8)
        bytes.append(salt)
        let digest = SHA256.hash(data: bytes)
        bytes.resetBytes(in: 0..<bytes.count)
        return Data(digest)
    }

    private func loadCred(email: String) -> Cred? {
        guard let data = KeychainBox.get(account: email) else { return nil }
        return try? JSONDecoder().decode(Cred.self, from: data)
    }

    private func timingSafeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    private struct Cred: Codable {
        var salt: Data
        var hash: Data
    }
}
