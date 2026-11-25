import Foundation
import Network

/// One `key: value` line of an MPD response.
public struct MPDPair: Sendable, Equatable {
    public let key: String
    public let value: String
}

/// Resumes a continuation exactly once, whichever callback fires first.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// A single TCP session with an MPD server, line protocol.
final class MPDConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "mpd-bar.mpd")
    private var buffer = Data()

    init(host: String, port: Int) throws {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else {
            throw PlayerError.unreachable("invalid port \(port)")
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        connection = NWConnection(host: NWEndpoint.Host(host), port: p,
                                  using: NWParameters(tls: nil, tcp: tcp))
    }

    func open() async throws {
        let once = OnceFlag()
        let conn = connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume() }
                case .failed(let err), .waiting(let err):
                    if once.claim() {
                        conn.cancel()
                        cont.resume(throwing: PlayerError.unreachable(err.localizedDescription))
                    }
                case .cancelled:
                    if once.claim() { cont.resume(throwing: PlayerError.unreachable("timed out")) }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    func send(_ text: String) async throws {
        let once = OnceFlag()
        let conn = connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(text.utf8), completion: .contentProcessed { err in
                guard once.claim() else { return }
                if let err {
                    cont.resume(throwing: PlayerError.unreachable(err.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveChunk() async throws -> Data {
        let conn = connection
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                if let err {
                    cont.resume(throwing: PlayerError.unreachable(err.localizedDescription))
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: PlayerError.protocolError("MPD closed the connection."))
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }

    /// Larger than any sane playlist answer; past it the server is misbehaving.
    static let maxResponseBytes = 8 * 1024 * 1024

    /// Reads one full response: lines up to and including "OK", "OK MPD x.y.z" or "ACK ...".
    func readResponse() async throws -> [String] {
        var emptyReads = 0
        while true {
            if Self.isComplete(buffer) {
                let lines = Self.lines(buffer)
                buffer.removeAll()
                return lines
            }
            if buffer.count > Self.maxResponseBytes {
                throw PlayerError.protocolError("MPD sent an oversized response.")
            }
            let chunk = try await receiveChunk()
            if chunk.isEmpty {
                emptyReads += 1
                if emptyReads > 20 { throw PlayerError.protocolError("MPD sent an incomplete response.") }
            }
            buffer.append(chunk)
        }
    }

    /// Looks at the last line only, so a long answer is not decoded again on every chunk.
    static func isComplete(_ data: Data) -> Bool {
        guard data.last == 0x0A else { return false }
        let body = data.dropLast()
        let start = body.lastIndex(of: 0x0A).map { body.index(after: $0) } ?? body.startIndex
        let last = String(decoding: body[start...], as: UTF8.self)
        return last == "OK" || last.hasPrefix("OK MPD ") || last.hasPrefix("ACK ")
    }

    /// Lossy decoding: one invalid byte in a tag must not stall every poll until the watchdog.
    static func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    static func completeResponse(_ data: Data) -> [String]? {
        isComplete(data) ? lines(data) : nil
    }

    func close() {
        connection.cancel()
    }
}

/// Returns `op`'s result, or throws "timed out" after `seconds`, whichever comes first.
/// Cancelling the caller cancels `op`; the timer stops as soon as `op` is done.
func withDeadline<T: Sendable>(seconds: UInt64,
                               _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    let once = OnceFlag()
    let work = Task { try await op() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let timer = Task {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                if !Task.isCancelled, once.claim() {
                    work.cancel()
                    cont.resume(throwing: PlayerError.unreachable("timed out"))
                }
            }
            Task {
                let r = await work.result
                timer.cancel()
                if once.claim() { cont.resume(with: r) }
            }
        }
    } onCancel: {
        work.cancel()
    }
}

/// Stateless MPD client: one short TCP session per exchange, commands sent as a command list.
public struct MPDClient: Sendable {
    public let host: String
    public let port: Int
    public let password: String?
    public var timeoutSeconds: UInt64 = 8

    public init(host: String, port: Int, password: String?) {
        self.host = host
        self.port = port
        self.password = password
    }

    public static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func ackMessage(_ line: String) -> String {
        // ACK [50@0] {play} No such song
        if let r = line.range(of: "} ") { return "MPD: " + line[r.upperBound...] }
        return "MPD: " + line
    }

    /// Sends the commands and returns one array of pairs per command. The deadline holds even
    /// if the connection never calls back after the watchdog cancels it.
    public func exchange(_ commands: [String]) async throws -> [[MPDPair]] {
        let client = self
        return try await withDeadline(seconds: timeoutSeconds + 2) { try await client.exchangeOnce(commands) }
    }

    func exchangeOnce(_ commands: [String]) async throws -> [[MPDPair]] {
        let conn = try MPDConnection(host: host, port: port)
        let limit = timeoutSeconds
        let watchdog = Task {
            try await Task.sleep(nanoseconds: limit * 1_000_000_000)
            conn.close()
        }
        defer {
            watchdog.cancel()
            conn.close()
        }

        return try await withTaskCancellationHandler {
            try await converse(conn, commands)
        } onCancel: {
            conn.close()
        }
    }

    private func converse(_ conn: MPDConnection, _ commands: [String]) async throws -> [[MPDPair]] {
        try await conn.open()
        let greeting = try await conn.readResponse()
        guard greeting.last?.hasPrefix("OK MPD") == true else {
            throw PlayerError.protocolError("Not an MPD server.")
        }

        var all: [String] = []
        let usePassword = !(password ?? "").isEmpty
        if usePassword, let pw = password { all.append("password " + Self.quote(pw)) }
        all += commands
        try await conn.send("command_list_ok_begin\n" + all.joined(separator: "\n") + "\ncommand_list_end\n")

        var results: [[MPDPair]] = []
        var current: [MPDPair] = []
        for line in try await conn.readResponse() {
            if line == "list_OK" {
                results.append(current)
                current = []
            } else if line == "OK" {
                break
            } else if line.hasPrefix("ACK ") {
                throw PlayerError.protocolError(Self.ackMessage(line))
            } else if let r = line.range(of: ": ") {
                current.append(MPDPair(key: String(line[..<r.lowerBound]), value: String(line[r.upperBound...])))
            }
        }
        if usePassword, !results.isEmpty { results.removeFirst() }
        return results
    }
}

/// MPD over its native TCP protocol (direct connection, LAN or VPN).
@MainActor
public final class MPDBackend: PlayerBackend {
    private let client: MPDClient
    private let playlist: String

    public init(host: String, port: Int, password: String?, playlist: String) {
        client = MPDClient(host: host, port: port, password: password)
        self.playlist = playlist
    }

    private func value(_ key: String, in pairs: [MPDPair]) -> String? {
        pairs.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    public func status() async throws -> PlayerStatus {
        let r = try await client.exchange(["status", "currentsong"])
        let st = r.first ?? []
        let song = r.count > 1 ? r[1] : []
        let state: PlaybackState
        switch value("state", in: st) {
        case "play": state = .playing
        case "pause": state = .paused
        default: state = .stopped
        }
        let vol = value("volume", in: st).flatMap(Int.init).flatMap { $0 < 0 ? nil : $0 }
        return PlayerStatus(state: state, volume: vol,
                            currentURI: value("file", in: song),
                            currentName: value("Name", in: song),
                            streamTitle: value("Title", in: song))
    }

    public func playlists() async throws -> [PlaylistRef] {
        let r = try await client.exchange(["listplaylists"])
        return (r.first ?? []).filter { $0.key == "playlist" }.map { PlaylistRef(name: $0.value, uri: $0.value) }
    }

    public func stations() async throws -> [Station] {
        let r: [[MPDPair]]
        do {
            r = try await client.exchange(["listplaylistinfo " + MPDClient.quote(playlist)])
        } catch PlayerError.protocolError(let msg) where msg.lowercased().contains("no such playlist") {
            let names = (try? await client.exchange(["listplaylists"]))?.first?
                .filter { $0.key == "playlist" }.map(\.value) ?? []
            throw PlayerError.playlistNotFound(playlist, available: names)
        }
        var out: [Station] = []
        var file: String?
        var name: String?
        var title: String?
        func flush() {
            if let f = file { out.append(Station(name: name ?? title ?? Station.fallbackName(for: f), uri: f)) }
        }
        for pair in r.first ?? [] {
            switch pair.key {
            case "file":
                flush()
                file = pair.value
                name = nil
                title = nil
            case "Name": name = pair.value
            case "Title": title = pair.value
            default: break
            }
        }
        flush()
        return out
    }

    public func play(_ station: Station) async throws {
        _ = try await client.exchange(["clear", "add " + MPDClient.quote(station.uri), "play"])
    }

    public func pause() async throws { _ = try await client.exchange(["pause 1"]) }
    public func resume() async throws { _ = try await client.exchange(["pause 0"]) }
    public func stop() async throws { _ = try await client.exchange(["stop"]) }

    public func setVolume(_ volume: Int) async throws {
        _ = try await client.exchange(["setvol \(max(0, min(100, volume)))"])
    }

    /// MPD has no mute; `status.muted` stays nil so the UI never offers it.
    public func setMute(_ muted: Bool) async throws {
        throw PlayerError.protocolError("MPD has no mute: set the volume to 0 instead.")
    }
}
