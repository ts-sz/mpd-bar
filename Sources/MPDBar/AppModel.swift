import MPDBarCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: AppConfig?
    @Published private(set) var configError: String?
    @Published var stations: [Station] = []
    @Published var status = PlayerStatus()
    @Published var volume: Double = 0
    @Published var error: String?
    @Published var busy = false
    @Published var showingSettings = false
    @Published var testMessage: String?
    @Published var testOK = false
    @Published var testing = false

    let configURL = ConfigFile.defaultURL
    var configPath: String { ConfigFile.display(configURL) }
    var configExists: Bool { FileManager.default.fileExists(atPath: configURL.path) }

    var isEditingVolume = false
    var isVisible = false {
        didSet { if isVisible && !oldValue { Task { await refresh() } } }
    }

    private var backend: PlayerBackend?
    private var pollTask: Task<Void, Never>?
    /// Modification date of the config file when it was last read; nil when it did not exist.
    private var configStamp: Date?
    private var configLoaded = false

    init() {
        loadConfig(force: true)
        showingSettings = config == nil
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let visible = self?.isVisible ?? false
                let seconds: UInt64 = visible ? 4 : 30
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    // MARK: Derived state

    var isPlaying: Bool { status.state == .playing }

    var currentStation: Station? { stations.first { $0.uri == status.currentURI } }

    var headline: String {
        if let s = currentStation { return s.name }
        if let n = status.currentName, !n.isEmpty { return n }
        if let u = status.currentURI { return Station.fallbackName(for: u) }
        return "Nothing playing"
    }

    var subtitle: String {
        if let t = status.streamTitle, !t.isEmpty, isPlaying, t != headline { return t }
        switch status.state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    // MARK: Config file

    /// Reads the config file again when it changed since the last read (or always with `force`).
    func loadConfig(force: Bool = false) {
        let stamp = ConfigFile.modificationDate(configURL)
        if configLoaded && !force && stamp == configStamp { return }
        configLoaded = true
        configStamp = stamp
        backend = nil
        stations = []
        error = nil
        testMessage = nil
        do {
            config = try ConfigFile.load(configURL)
            configError = nil
        } catch {
            config = nil
            configError = error.localizedDescription
            showingSettings = true
        }
    }

    /// Writes the template when there is no file yet, then opens it in the default text editor.
    func createConfig() {
        if !configExists {
            do {
                try ConfigFile.write(.template, to: configURL)
            } catch {
                configError = error.localizedDescription
                return
            }
        }
        loadConfig(force: true)
        openConfig()
    }

    func openConfig() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", configURL.path]
        try? p.run()
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func reloadConfig() async {
        loadConfig(force: true)
        await refresh()
    }

    func test() async {
        loadConfig(force: true)
        guard let config else { return }
        testing = true
        defer { testing = false }
        do {
            let b = try config.makeBackend()
            let st = try await b.status()
            let list = try await b.stations()
            testOK = true
            testMessage = "Connected: \(st.state.rawValue), \(list.count) stations."
        } catch {
            testOK = false
            testMessage = error.localizedDescription
        }
    }

    // MARK: Backend

    private func currentBackend() throws -> PlayerBackend {
        if let b = backend { return b }
        guard let config else { throw PlayerError.notConfigured }
        let b = try config.makeBackend()
        backend = b
        return b
    }

    func refresh() async {
        loadConfig()
        guard config != nil else { return }
        do {
            let b = try currentBackend()
            if stations.isEmpty { stations = try await b.stations() }
            let s = try await b.status()
            status = s
            if !isEditingVolume, let v = s.volume { volume = Double(v) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reloadStations() async {
        stations = []
        backend = nil
        await refresh()
    }

    private func run(_ body: @MainActor (PlayerBackend) async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await body(try currentBackend())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await refresh()
    }

    // MARK: Actions

    func play(_ s: Station) async {
        status.currentURI = s.uri
        await run { try await $0.play(s) }
    }

    func togglePlay() async {
        switch status.state {
        case .playing: await run { try await $0.pause() }
        case .paused: await run { try await $0.resume() }
        case .stopped:
            if let s = currentStation ?? stations.first { await play(s) }
        }
    }

    func stop() async { await run { try await $0.stop() } }

    func step(_ delta: Int) async {
        guard !stations.isEmpty else { return }
        let i = stations.firstIndex { $0.uri == status.currentURI } ?? -1
        let n = stations.count
        await play(stations[((i + delta) % n + n) % n])
    }

    func setVolume(_ v: Int) async {
        let clamped = max(0, min(100, v))
        volume = Double(clamped)
        await run { try await $0.setVolume(clamped) }
    }
}
