import Foundation
import Security

public enum BackendKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mopidy, mpd
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .mopidy: return "Mopidy (HTTP)"
        case .mpd: return "MPD (TCP)"
        }
    }
}

public enum MopidyAuth: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, cloudflareAccess
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "Direct"
        case .cloudflareAccess: return "Cloudflare Access"
        }
    }
}

/// Non-secret settings, stored in UserDefaults. Secrets live in the Keychain.
public struct PlayerSettings: Codable, Equatable, Sendable {
    public var backend: BackendKind = .mopidy
    public var mopidyURL: String = "http://localhost:6680"
    public var mopidyAuth: MopidyAuth = .none
    public var mpdHost: String = "localhost"
    public var mpdPort: Int = 6600
    public var playlist: String = ""

    public init() {}

    static let defaultsKey = "settings.v1"

    public static func load() -> PlayerSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(PlayerSettings.self, from: data) else {
            return PlayerSettings()
        }
        return s
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    public var isConfigured: Bool {
        let hasServer = backend == .mopidy
            ? !mopidyURL.trimmingCharacters(in: .whitespaces).isEmpty
            : !mpdHost.trimmingCharacters(in: .whitespaces).isEmpty
        return hasServer && !playlist.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Generic passwords in the login Keychain, service "mpd-bar".
public enum Keychain {
    public static let service = "mpd-bar"
    public static let cfClientID = "cf-client-id"
    public static let cfClientSecret = "cf-client-secret"
    public static let mpdPassword = "mpd-password"

    public static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    public static func write(_ account: String, _ value: String) -> Bool {
        delete(account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public struct Credentials: Sendable {
    public var cfClientID: String?
    public var cfClientSecret: String?
    public var mpdPassword: String?

    public init(cfClientID: String? = nil, cfClientSecret: String? = nil, mpdPassword: String? = nil) {
        self.cfClientID = cfClientID
        self.cfClientSecret = cfClientSecret
        self.mpdPassword = mpdPassword
    }

    public static func fromKeychain() -> Credentials {
        Credentials(cfClientID: Keychain.read(Keychain.cfClientID),
                    cfClientSecret: Keychain.read(Keychain.cfClientSecret),
                    mpdPassword: Keychain.read(Keychain.mpdPassword))
    }
}

public enum BackendFactory {
    @MainActor
    public static func make(_ s: PlayerSettings, credentials c: Credentials) throws -> PlayerBackend {
        guard s.isConfigured else { throw PlayerError.notConfigured }
        let playlist = s.playlist.trimmingCharacters(in: .whitespaces)
        switch s.backend {
        case .mopidy:
            let useCF = s.mopidyAuth == .cloudflareAccess
            if useCF && (c.cfClientID == nil || c.cfClientSecret == nil) { throw PlayerError.accessDenied }
            return try MopidyBackend(baseURL: s.mopidyURL, playlist: playlist,
                                     cfClientID: useCF ? c.cfClientID : nil,
                                     cfClientSecret: useCF ? c.cfClientSecret : nil)
        case .mpd:
            return MPDBackend(host: s.mpdHost.trimmingCharacters(in: .whitespaces), port: s.mpdPort,
                              password: c.mpdPassword, playlist: playlist)
        }
    }
}
