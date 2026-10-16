import Foundation
import MPDBarCore

/// Command-line check of a server, without the UI.
///   mpdbar-probe                      tests the server in ~/.config/mpd-bar/config.json, like the app
///   mpdbar-probe init                 writes a template config file
///   mpdbar-probe playlists            lists the server's stored playlists
///   mpdbar-probe use NAME             checks NAME on the server and writes it to the config file
///   mpdbar-probe --mopidy URL ... / --mpd HOST[:PORT] ...   without a config file
/// Read-only by default. --write plays the first station, sets the volume, then stops.
@main
struct Probe {
    static let usage = """
    mpdbar-probe \(Version.string)
    usage: mpdbar-probe [--config PATH] [--write]       test the server in the config file
           mpdbar-probe init [--config PATH]            write a template config file
           mpdbar-probe playlists [WORD] [--config PATH] list the server's playlists, WORD filters
           mpdbar-probe use NAME [--config PATH]        pick a playlist, saved in the config file
           mpdbar-probe (--mopidy URL | --mpd HOST[:PORT]) (--playlist NAME [--write] | playlists)
    config: \(ConfigFile.display(ConfigFile.defaultURL)) (override with --config or MPDBAR_CONFIG)
    env:    CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET, MPD_PASSWORD (with --mopidy / --mpd)
    """

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        print("FAIL: \(message)")
        exit(code)
    }

    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("--help") || args.contains("-h") {
            print(usage)
            exit(0)
        }
        // Positional words: everything that is neither a flag nor a flag's value.
        let valued: Set<String> = ["--config", "--mopidy", "--mpd", "--playlist"]
        var words: [String] = []
        var i = 1
        while i < args.count {
            if valued.contains(args[i]) { i += 2; continue }
            if !args[i].hasPrefix("-") { words.append(args[i]) }
            i += 1
        }
        let command = words.first ?? "check"
        guard ["check", "init", "playlists", "use"].contains(command) else {
            print("unknown command \"\(command)\"\n")
            print(usage)
            exit(2)
        }

        let env = ProcessInfo.processInfo.environment
        let configURL = value("--config").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? ConfigFile.defaultURL
        let shown = ConfigFile.display(configURL)

        if command == "init" {
            if FileManager.default.fileExists(atPath: configURL.path) {
                print("\(shown) already exists, left unchanged.")
                exit(0)
            }
            do {
                try ConfigFile.write(.template, to: configURL)
            } catch {
                fail(error.localizedDescription)
            }
            print("Wrote \(shown) (mode 600). Set the server in it, then run: mpdbar-probe playlists")
            exit(0)
        }

        let needsPlaylist = command == "check"
        var config: AppConfig?
        let backend: PlayerBackend
        do {
            if let mpd = value("--mpd") {
                let playlist = value("--playlist") ?? ""
                if needsPlaylist && playlist.isEmpty { print(usage); exit(2) }
                let parts = mpd.split(separator: ":", maxSplits: 1).map(String.init)
                let port = parts.count > 1 ? Int(parts[1]) ?? 6600 : 6600
                backend = MPDBackend(host: parts[0], port: port, password: env["MPD_PASSWORD"], playlist: playlist)
            } else if let url = value("--mopidy") {
                let playlist = value("--playlist") ?? ""
                if needsPlaylist && playlist.isEmpty { print(usage); exit(2) }
                backend = try MopidyBackend(baseURL: url, playlist: playlist,
                                            cfClientID: env["CF_ACCESS_CLIENT_ID"],
                                            cfClientSecret: env["CF_ACCESS_CLIENT_SECRET"])
            } else {
                let loaded: AppConfig
                do {
                    loaded = try ConfigFile.load(configURL, requirePlaylist: needsPlaylist)
                } catch ConfigError.missing(let path) {
                    print("No config file at \(path). Create one with: mpdbar-probe init\n")
                    print(usage)
                    exit(2)
                }
                config = loaded
                print("config: \(shown)")
                print("server: \(loaded.summary)")
                backend = try loaded.makeBackend(requirePlaylist: needsPlaylist)
            }
        } catch {
            fail(error.localizedDescription)
        }

        switch command {
        case "playlists":
            await listPlaylists(backend, filter: words.dropFirst().joined(separator: " "))
        case "use":
            guard words.count > 1 else { print(usage); exit(2) }
            guard var cfg = config else { fail("\"use\" saves to the config file: drop --mopidy / --mpd.", code: 2) }
            await use(words.dropFirst().joined(separator: " "), backend: backend, config: &cfg, at: configURL)
        default:
            await check(backend, write: args.contains("--write"))
        }
    }

    @MainActor
    static func listPlaylists(_ backend: PlayerBackend, filter: String) async {
        do {
            var all = try await backend.playlists()
            let total = all.count
            if !filter.isEmpty {
                all = all.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.uri.localizedCaseInsensitiveContains(filter) }
                print("playlists: \(all.count) of \(total) match \"\(filter)\"")
            } else {
                print("playlists: \(total)")
            }
            let width = min(40, all.map(\.name.count).max() ?? 0)
            for p in all.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let pad = String(repeating: " ", count: max(0, width - p.name.count))
                print(p.uri == p.name ? "  \(p.name)" : "  \(p.name)\(pad)  \(p.uri)")
            }
            if !all.isEmpty { print("Pick one with: mpdbar-probe use NAME") }
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    @MainActor
    static func use(_ wanted: String, backend: PlayerBackend, config: inout AppConfig, at url: URL) async {
        do {
            let all = try await backend.playlists()
            guard let match = all.first(where: { $0.name == wanted || $0.uri == wanted })
                ?? all.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else {
                let names = all.map(\.name).sorted().prefix(20).joined(separator: ", ")
                fail("playlist \"\(wanted)\" not found. Available: \(names)")
            }
            // Two playlists with the same name (Mopidy, several sources): keep the unambiguous URI.
            let duplicate = all.filter { $0.name.caseInsensitiveCompare(match.name) == .orderedSame }.count > 1
            config.playlist = duplicate ? match.uri : match.name
            let stations = try await config.makeBackend().stations()
            try ConfigFile.write(config, to: url)
            print("ok   playlist \"\(config.playlist)\", \(stations.count) stations, saved to \(ConfigFile.display(url))")
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    @MainActor
    static func check(_ backend: PlayerBackend, write: Bool) async {
        func expect(_ ok: Bool, _ what: String) {
            print("\(ok ? "ok  " : "FAIL") \(what)")
            if !ok { exit(1) }
        }
        do {
            let st = try await backend.status()
            let mute = st.muted == true ? ", MUTED (no sound until unmuted)" : ""
            print("status: \(st.state.rawValue), volume \(st.volume.map(String.init) ?? "n/a")\(mute)")
            let stations = try await backend.stations()
            print("stations: \(stations.count)")
            for s in stations.prefix(5) { print("  - \(s.name)  \(s.uri)") }
            expect(!stations.isEmpty, "playlist has stations")

            if write {
                try await backend.play(stations[0])
                let playing = try await backend.status()
                expect(playing.currentURI == stations[0].uri, "play queues the first station (state \(playing.state.rawValue))")

                if playing.volume != nil {
                    try await backend.setVolume(37)
                    let v = try await backend.status().volume
                    expect(v == 37, "volume set to 37 (read \(v.map(String.init) ?? "n/a"))")
                } else {
                    print("skip volume: server reports no mixer")
                }

                try await backend.stop()
                let stopped = try await backend.status()
                expect(stopped.state == .stopped, "stop")
            }
            print("OK")
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }
}
