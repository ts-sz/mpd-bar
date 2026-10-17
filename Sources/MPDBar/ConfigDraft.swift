import MPDBarCore
import SwiftUI

/// One connection preset of the Settings panel. Each mode maps to a shape of the config file:
/// Cloudflare Access and Mopidy direct both write a `mopidy` section, MPD writes the `mpd` one.
enum ConnectionMode: String, CaseIterable, Identifiable {
    case cloudflare, mopidyDirect, mpd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .mopidyDirect: return "Direct"
        case .mpd: return "MPD"
        }
    }
}

/// Editable copy of the config shown in the Settings panel. A reference type holding every
/// field, so no view mutates its own stored state. The config file stays the single store:
/// saving writes it through `ConfigFile` and the app reloads from disk, so hand edits and
/// panel edits can never diverge.
@MainActor
final class ConfigDraft: ObservableObject {
    @Published var mode: ConnectionMode = .cloudflare
    @Published var serverURL = ""
    @Published var clientID = ""
    @Published var clientSecret = ""
    @Published var mpdHost = ""
    @Published var mpdPort = ""
    @Published var mpdPassword = ""
    @Published var playlist = ""

    func load(from config: AppConfig?) {
        playlist = config?.playlist ?? ""
        if let d = config?.mpd {
            mode = .mpd
            mpdHost = d.host
            mpdPort = d.port.map(String.init) ?? ""
            mpdPassword = d.password ?? ""
            serverURL = ""
            clientID = ""
            clientSecret = ""
        } else if let m = config?.mopidy {
            mode = m.cloudflareAccess == nil ? .mopidyDirect : .cloudflare
            serverURL = m.url
            clientID = m.cloudflareAccess?.clientId ?? ""
            clientSecret = m.cloudflareAccess?.clientSecret ?? ""
            mpdHost = ""
            mpdPort = ""
            mpdPassword = ""
        } else {
            mode = .cloudflare
            serverURL = ""
            clientID = ""
            clientSecret = ""
            mpdHost = ""
            mpdPort = ""
            mpdPassword = ""
        }
    }

    func makeConfig(requirePlaylist: Bool = true) throws -> AppConfig {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let config: AppConfig
        switch mode {
        case .cloudflare, .mopidyDirect:
            var m = AppConfig.Mopidy(url: trim(serverURL))
            if mode == .cloudflare {
                m.cloudflareAccess = AppConfig.CloudflareAccess(clientId: trim(clientID), clientSecret: trim(clientSecret))
            }
            config = AppConfig(backend: .mopidy, playlist: trim(playlist), mopidy: m)
        case .mpd:
            let portText = trim(mpdPort)
            guard portText.isEmpty || Int(portText) != nil else {
                throw ConfigError.invalid("\"mpd.port\" should be a number.")
            }
            let password = trim(mpdPassword)
            config = AppConfig(backend: .mpd, playlist: trim(playlist),
                               mpd: AppConfig.MPD(host: trim(mpdHost), port: portText.isEmpty ? nil : Int(portText),
                                                  password: password.isEmpty ? nil : password))
        }
        try config.validate(requirePlaylist: requirePlaylist)
        return config
    }
}

/// State of the in-panel playlist browser: the server's playlists, filtered, with a track count
/// for the selected one. Counts are fetched on demand only.
@MainActor
struct PlaylistBrowser {
    var items: [PlaylistRef] = []
    var filter = ""
    var loading = false
    var counting = false
    var count: Int?
    var error: String?
}
