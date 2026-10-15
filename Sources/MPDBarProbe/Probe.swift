import Foundation
import MPDBarCore

/// Command-line check of a server, without the UI.
///   mpdbar-probe --mopidy http://host:6680 --playlist radios
///   mpdbar-probe --mpd host:6600 --playlist radios [--write]
/// Cloudflare Access: CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET. MPD password: MPD_PASSWORD.
/// Read-only by default. --write plays the first station, sets the volume, then stops.
@main
struct Probe {
    static let usage = """
    usage: mpdbar-probe (--mopidy URL | --mpd HOST[:PORT]) --playlist NAME [--write]
    env:   CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET (Mopidy behind Cloudflare Access)
           MPD_PASSWORD (MPD with a password)
    """

    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let env = ProcessInfo.processInfo.environment
        guard let playlist = value("--playlist") else {
            print(usage)
            exit(2)
        }

        let backend: PlayerBackend
        do {
            if let mpd = value("--mpd") {
                let parts = mpd.split(separator: ":", maxSplits: 1).map(String.init)
                let port = parts.count > 1 ? Int(parts[1]) ?? 6600 : 6600
                backend = MPDBackend(host: parts[0], port: port, password: env["MPD_PASSWORD"], playlist: playlist)
            } else if let url = value("--mopidy") {
                backend = try MopidyBackend(baseURL: url, playlist: playlist,
                                            cfClientID: env["CF_ACCESS_CLIENT_ID"],
                                            cfClientSecret: env["CF_ACCESS_CLIENT_SECRET"])
            } else {
                print(usage)
                exit(2)
            }
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }

        func check(_ ok: Bool, _ what: String) {
            print("\(ok ? "ok  " : "FAIL") \(what)")
            if !ok { exit(1) }
        }

        do {
            let st = try await backend.status()
            print("status: \(st.state.rawValue), volume \(st.volume.map(String.init) ?? "n/a")")
            let stations = try await backend.stations()
            print("stations: \(stations.count)")
            for s in stations.prefix(5) { print("  - \(s.name)  \(s.uri)") }
            check(!stations.isEmpty, "playlist has stations")

            if args.contains("--write") {
                try await backend.play(stations[0])
                let playing = try await backend.status()
                check(playing.currentURI == stations[0].uri, "play queues the first station (state \(playing.state.rawValue))")

                if playing.volume != nil {
                    try await backend.setVolume(37)
                    let v = try await backend.status().volume
                    check(v == 37, "volume set to 37 (read \(v.map(String.init) ?? "n/a"))")
                } else {
                    print("skip volume: server reports no mixer")
                }

                try await backend.stop()
                let stopped = try await backend.status()
                check(stopped.state == .stopped, "stop")
            }
            print("OK")
            exit(0)
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
