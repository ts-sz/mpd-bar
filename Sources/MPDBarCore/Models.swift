import Foundation

public enum Version {
    public static let string = "0.1.1"
}

/// One entry of the station playlist.
public struct Station: Identifiable, Hashable, Sendable {
    public let name: String
    public let uri: String
    public var id: String { uri }

    public init(name: String, uri: String) {
        self.name = name
        self.uri = uri
    }

    /// Readable fallback when the server gives no title: the stream host.
    public static func fallbackName(for uri: String) -> String {
        if let host = URL(string: uri)?.host, !host.isEmpty { return host }
        return uri
    }
}

public enum PlaybackState: String, Sendable {
    case playing, paused, stopped
}

public struct PlayerStatus: Sendable, Equatable {
    public var state: PlaybackState
    public var volume: Int?
    public var currentURI: String?
    public var currentName: String?
    public var streamTitle: String?

    public init(state: PlaybackState = .stopped, volume: Int? = nil, currentURI: String? = nil,
                currentName: String? = nil, streamTitle: String? = nil) {
        self.state = state
        self.volume = volume
        self.currentURI = currentURI
        self.currentName = currentName
        self.streamTitle = streamTitle
    }
}

public enum PlayerError: LocalizedError, Sendable {
    case notConfigured
    case invalidURL(String)
    case accessDenied
    case http(Int)
    case unreachable(String)
    case protocolError(String)
    case playlistNotFound(String, available: [String])

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Not configured yet. Open Settings."
        case .invalidURL(let s):
            return "Invalid server URL: \(s)"
        case .accessDenied:
            return "Access denied. Check the Cloudflare Access client ID and secret."
        case .http(let code):
            return "Server returned HTTP \(code)."
        case .unreachable(let why):
            return "Server unreachable (\(why))."
        case .protocolError(let why):
            return why
        case .playlistNotFound(let name, let available):
            let list = available.prefix(8).joined(separator: ", ")
            return available.isEmpty
                ? "Playlist \"\(name)\" not found."
                : "Playlist \"\(name)\" not found. Available: \(list)"
        }
    }
}

/// What every server type provides to the UI.
@MainActor
public protocol PlayerBackend: AnyObject {
    func status() async throws -> PlayerStatus
    func stations() async throws -> [Station]
    func play(_ station: Station) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func setVolume(_ volume: Int) async throws
}
