import Foundation

/// Mopidy over its HTTP JSON-RPC API (`/mopidy/rpc`), optionally behind
/// Cloudflare Access with a service token.
@MainActor
public final class MopidyBackend: PlayerBackend {
    private let endpoint: URL
    private let headers: [String: String]
    private let playlist: String
    private var playlistURI: String?

    public init(baseURL: String, playlist: String, cfClientID: String?, cfClientSecret: String?) throws {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/mopidy/rpc") { s += "/mopidy/rpc" }
        guard let url = URL(string: s), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil else {
            throw PlayerError.invalidURL(baseURL)
        }
        endpoint = url
        var h = ["Content-Type": "application/json", "User-Agent": "mpd-bar/\(Version.string)"]
        if let id = cfClientID, let secret = cfClientSecret {
            h["CF-Access-Client-Id"] = id
            h["CF-Access-Client-Secret"] = secret
        }
        headers = h
        self.playlist = playlist
    }

    // MARK: JSON-RPC

    /// Runs several calls in one HTTP request (JSON-RPC 2.0 batch); results in call order.
    func batch(_ calls: [(String, [String: Any])]) async throws -> [Any?] {
        let payload: [[String: Any]] = calls.enumerated().map { i, c in
            ["jsonrpc": "2.0", "id": i + 1, "method": c.0, "params": c.1]
        }
        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw PlayerError.unreachable(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw PlayerError.unreachable("no HTTP response") }
        // Cloudflare Access answers an unauthenticated request with a redirect to its login page.
        if http.url?.host != endpoint.host || [401, 403].contains(http.statusCode) {
            throw PlayerError.accessDenied
        }
        guard http.statusCode == 200 else { throw PlayerError.http(http.statusCode) }
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PlayerError.protocolError("Unexpected answer: is this a Mopidy server?")
        }
        var byID: [Int: Any] = [:]
        for item in items {
            guard let id = item["id"] as? Int else { continue }
            if let err = item["error"] as? [String: Any] {
                throw PlayerError.protocolError("Mopidy: \(err["message"] as? String ?? "error")")
            }
            if let r = item["result"], !(r is NSNull) { byID[id] = r }
        }
        return (1...calls.count).map { byID[$0] }
    }

    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> Any? {
        try await batch([(method, params)]).first ?? nil
    }

    // MARK: PlayerBackend

    public func status() async throws -> PlayerStatus {
        let r = try await batch([
            ("core.playback.get_state", [:]),
            ("core.playback.get_current_track", [:]),
            ("core.playback.get_stream_title", [:]),
            ("core.mixer.get_volume", [:]),
        ])
        let track = r[1] as? [String: Any]
        return PlayerStatus(
            state: PlaybackState(rawValue: (r[0] as? String) ?? "stopped") ?? .stopped,
            volume: r[3] as? Int,
            currentURI: track?["uri"] as? String,
            currentName: track?["name"] as? String,
            streamTitle: r[2] as? String)
    }

    private func resolvePlaylistURI() async throws -> String {
        if let uri = playlistURI { return uri }
        if playlist.contains(":") {           // already a URI, e.g. m3u:radios.m3u8
            playlistURI = playlist
            return playlist
        }
        let all = (try await call("core.playlists.as_list") as? [[String: Any]]) ?? []
        let names = all.compactMap { $0["name"] as? String }
        guard let match = all.first(where: {
            ($0["name"] as? String)?.caseInsensitiveCompare(playlist) == .orderedSame
        }), let uri = match["uri"] as? String else {
            throw PlayerError.playlistNotFound(playlist, available: names)
        }
        playlistURI = uri
        return uri
    }

    public func playlists() async throws -> [PlaylistRef] {
        let all = (try await call("core.playlists.as_list") as? [[String: Any]]) ?? []
        return all.compactMap { p in
            guard let uri = p["uri"] as? String else { return nil }
            return PlaylistRef(name: (p["name"] as? String) ?? uri, uri: uri)
        }
    }

    public func stations() async throws -> [Station] {
        let uri = try await resolvePlaylistURI()
        let pl = try await call("core.playlists.lookup", ["uri": uri]) as? [String: Any]
        guard let pl else { throw PlayerError.playlistNotFound(playlist, available: []) }
        let tracks = pl["tracks"] as? [[String: Any]] ?? []
        return tracks.compactMap { t in
            guard let u = t["uri"] as? String else { return nil }
            let name = (t["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Station.fallbackName(for: u)
            return Station(name: name, uri: u)
        }
    }

    public func play(_ station: Station) async throws {
        _ = try await batch([
            ("core.playback.stop", [:]),
            ("core.tracklist.clear", [:]),
            ("core.tracklist.add", ["uris": [station.uri]]),
            ("core.playback.play", [:]),
        ])
    }

    public func pause() async throws { _ = try await call("core.playback.pause") }
    public func resume() async throws { _ = try await call("core.playback.resume") }
    public func stop() async throws { _ = try await call("core.playback.stop") }

    public func setVolume(_ volume: Int) async throws {
        _ = try await call("core.mixer.set_volume", ["volume": max(0, min(100, volume))])
    }
}
