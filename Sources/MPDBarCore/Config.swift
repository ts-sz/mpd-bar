import Foundation

/// Contents of `~/.config/mpd-bar/config.json`.
///
/// ```json
/// {
///   "backend": "mopidy",
///   "playlist": "radios",
///   "mopidy": {
///     "url": "https://music.example.com",
///     "cloudflare_access": { "client_id": "...", "client_secret": "..." }
///   },
///   "mpd": { "host": "music.local", "port": 6600, "password": "" }
/// }
/// ```
public struct AppConfig: Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Sendable {
        case mopidy, mpd
    }

    public struct CloudflareAccess: Codable, Equatable, Sendable {
        public var clientId: String
        public var clientSecret: String

        public init(clientId: String, clientSecret: String) {
            self.clientId = clientId
            self.clientSecret = clientSecret
        }
    }

    public struct Mopidy: Codable, Equatable, Sendable {
        public var url: String
        public var cloudflareAccess: CloudflareAccess?

        public init(url: String, cloudflareAccess: CloudflareAccess? = nil) {
            self.url = url
            self.cloudflareAccess = cloudflareAccess
        }
    }

    public struct MPD: Codable, Equatable, Sendable {
        public var host: String
        public var port: Int?
        public var password: String?

        public init(host: String, port: Int? = nil, password: String? = nil) {
            self.host = host
            self.port = port
            self.password = password
        }
    }

    public var backend: Backend
    public var playlist: String
    public var mopidy: Mopidy?
    public var mpd: MPD?

    public init(backend: Backend, playlist: String, mopidy: Mopidy? = nil, mpd: MPD? = nil) {
        self.backend = backend
        self.playlist = playlist
        self.mopidy = mopidy
        self.mpd = mpd
    }

    /// Placeholder written by `mpdbar-probe init` and the app's "Create config file" button.
    public static let template = AppConfig(
        backend: .mopidy,
        playlist: "radios",
        mopidy: Mopidy(url: "http://music.local:6680"),
        mpd: MPD(host: "music.local", port: 6600, password: ""))

    private static func blank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Semantic checks the JSON decoder cannot make. Throws `ConfigError.invalid`.
    public func validate() throws {
        if Self.blank(playlist) { throw ConfigError.invalid("\"playlist\" is empty.") }
        switch backend {
        case .mopidy:
            guard let m = mopidy else { throw ConfigError.invalid("\"backend\" is \"mopidy\" but there is no \"mopidy\" section.") }
            if Self.blank(m.url) { throw ConfigError.invalid("\"mopidy.url\" is empty.") }
            if let cf = m.cloudflareAccess {
                if Self.blank(cf.clientId) { throw ConfigError.invalid("\"mopidy.cloudflare_access.client_id\" is empty.") }
                if Self.blank(cf.clientSecret) { throw ConfigError.invalid("\"mopidy.cloudflare_access.client_secret\" is empty.") }
            }
        case .mpd:
            guard let d = mpd else { throw ConfigError.invalid("\"backend\" is \"mpd\" but there is no \"mpd\" section.") }
            if Self.blank(d.host) { throw ConfigError.invalid("\"mpd.host\" is empty.") }
            if let p = d.port, !(1...65535).contains(p) { throw ConfigError.invalid("\"mpd.port\" must be 1-65535.") }
        }
    }

    @MainActor
    public func makeBackend() throws -> PlayerBackend {
        try validate()
        let name = playlist.trimmingCharacters(in: .whitespacesAndNewlines)
        switch backend {
        case .mopidy:
            let m = mopidy!
            let cf = m.cloudflareAccess
            return try MopidyBackend(
                baseURL: m.url, playlist: name,
                cfClientID: cf?.clientId.trimmingCharacters(in: .whitespacesAndNewlines),
                cfClientSecret: cf?.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        case .mpd:
            let d = mpd!
            let pw = (d.password ?? "").isEmpty ? nil : d.password
            return MPDBackend(host: d.host.trimmingCharacters(in: .whitespacesAndNewlines),
                              port: d.port ?? 6600, password: pw, playlist: name)
        }
    }

    /// One-line description with every secret masked, for the panel and the probe.
    public var summary: String {
        switch backend {
        case .mopidy:
            let url = mopidy?.url ?? "?"
            let auth = mopidy?.cloudflareAccess == nil ? "direct" : "Cloudflare Access"
            return "Mopidy \(url) (\(auth)), playlist \"\(playlist)\""
        case .mpd:
            let host = mpd?.host ?? "?"
            let port = mpd?.port ?? 6600
            let pw = (mpd?.password ?? "").isEmpty ? "" : ", password set"
            return "MPD \(host):\(port)\(pw), playlist \"\(playlist)\""
        }
    }
}

public enum ConfigError: LocalizedError, Sendable {
    case missing(String)
    case unreadable(String, String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let path):
            return "No config file at \(path)."
        case .unreadable(let path, let why):
            return "Cannot read \(path): \(why)"
        case .invalid(let why):
            return "Config error: \(why)"
        }
    }
}

public enum ConfigFile {
    /// `$MPDBAR_CONFIG`, else `$XDG_CONFIG_HOME/mpd-bar/config.json`, else `~/.config/mpd-bar/config.json`.
    public static var defaultURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["MPDBAR_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let base: URL
        if let x = env["XDG_CONFIG_HOME"], !x.isEmpty {
            base = URL(fileURLWithPath: (x as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("mpd-bar", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Path with the home directory shortened to `~`.
    public static func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    public static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Restricts the file to its owner (0600). Returns true when the mode had to change.
    @discardableResult
    public static func restrictPermissions(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let mode = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber else {
            return false
        }
        if mode.intValue & 0o077 == 0 { return false }
        return (try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)) != nil
    }

    public static func load(_ url: URL = defaultURL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ConfigError.missing(display(url)) }
        restrictPermissions(url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(display(url), error.localizedDescription)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config: AppConfig
        do {
            config = try decoder.decode(AppConfig.self, from: data)
        } catch let e as DecodingError {
            throw ConfigError.invalid(describe(e))
        }
        try config.validate()
        return config
    }

    public static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config) + Data("\n".utf8)
    }

    /// Writes atomically with mode 0600, creating the directory with mode 0700.
    public static func write(_ config: AppConfig, to url: URL = defaultURL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let createdDir = !fm.fileExists(atPath: dir.path)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if createdDir { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        let tmp = dir.appendingPathComponent(".config.json.\(ProcessInfo.processInfo.processIdentifier).tmp")
        guard fm.createFile(atPath: tmp.path, contents: try encode(config), attributes: [.posixPermissions: 0o600]) else {
            throw ConfigError.unreadable(display(tmp), "cannot write")
        }
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
        restrictPermissions(url)
    }

    static func path(_ keys: [CodingKey]) -> String {
        let parts = keys.map { k -> String in
            if let i = k.intValue { return "[\(i)]" }
            return snake(k.stringValue)
        }
        return parts.joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
    }

    static func snake(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isUppercase {
                out += "_" + ch.lowercased()
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // `if case` rather than `switch`: DecodingError may gain cases, and both `default` and
    // `@unknown default` draw a warning on some toolchains (CI builds with warnings as errors).
    static func describe(_ e: DecodingError) -> String {
        if case .keyNotFound(let key, let ctx) = e {
            return "missing key \"\(path(ctx.codingPath + [key]))\"."
        }
        if case .typeMismatch(let type, let ctx) = e {
            return "\"\(path(ctx.codingPath))\" should be \(typeName(type))."
        }
        if case .valueNotFound(let type, let ctx) = e {
            return "\"\(path(ctx.codingPath))\" is null, expected \(typeName(type))."
        }
        if case .dataCorrupted(let ctx) = e {
            if ctx.codingPath.isEmpty {
                let detail = (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                return "not valid JSON" + (detail.map { " (\($0))" } ?? "") + "."
            }
            if ctx.codingPath.last?.stringValue == "backend" {
                return "\"backend\" must be \"mopidy\" or \"mpd\"."
            }
            return "\"\(path(ctx.codingPath))\": \(ctx.debugDescription)"
        }
        return e.localizedDescription
    }

    static func typeName(_ t: Any.Type) -> String {
        switch t {
        case is String.Type: return "a string"
        case is Int.Type: return "a number"
        default: return "an object"
        }
    }
}
