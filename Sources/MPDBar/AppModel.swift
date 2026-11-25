import MPDBarCore
import SwiftUI

/// Volume shown by the panel, kept out of `AppModel` so a slider drag or a -/+ click
/// redraws the volume row only, not the whole panel and the menu bar label.
@MainActor
final class VolumeState: ObservableObject {
    @Published var value: Double = 0
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: AppConfig?
    @Published private(set) var configError: String?
    @Published var stations: [Station] = []
    /// True once the playlist was read, even when it is empty.
    @Published private(set) var stationsLoaded = false
    @Published private(set) var stationsError: String?
    @Published var status = PlayerStatus()
    @Published var error: String?
    @Published var busy = false
    @Published var showingSettings = false
    @Published var testMessage: String?
    @Published var testOK = false
    @Published var testing = false
    @Published var saveError: String?
    @Published var browse: PlaylistBrowser?

    let vol = VolumeState()
    var volume: Double {
        get { vol.value }
        set { if vol.value != newValue { vol.value = newValue } }
    }

    /// Editable copy shown by the Settings panel; written back through `ConfigFile` on Save.
    let draft = ConfigDraft()

    let configURL = ConfigFile.defaultURL
    var configPath: String { ConfigFile.display(configURL) }
    var configExists: Bool { FileManager.default.fileExists(atPath: configURL.path) }

    var isEditingVolume = false
    var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            if !isVisible { isEditingVolume = false }
            // Restart the loop so opening the panel does not wait out a 30 s sleep.
            startPolling(refreshFirst: isVisible)
        }
    }

    private var backend: PlayerBackend?
    private var pollTask: Task<Void, Never>?
    /// Modification date of the config file when it was last read; nil when it did not exist.
    private var configStamp: Date?
    private var configLoaded = false

    /// Polls and actions run one at a time through this chain, so a poll never lands between
    /// an action and its result, and requests reach the server in click order.
    private var tail: Task<Void, Never>?
    /// Bumped by every action and backend reset: a poll started before discards its result.
    private var epoch = 0
    private var pendingActions = 0
    /// The poll queued or running in the chain; an action cancels it instead of waiting for it.
    private var pollOp: Task<Void, Never>?
    private var pollQueued = false
    private var stationsRetryAt = Date.distantPast
    /// Latest-wins counters: a queued play or volume superseded by a later click is skipped.
    private var playIntent = 0
    private var volumeIntent = 0
    private var volumeSend: Task<Void, Never>?
    /// Until then, a poll does not overwrite the volume shown: it may predate the last change.
    private var volumeHoldUntil = Date.distantPast
    private var testToken = 0
    private var browseToken = 0
    private var countToken = 0

    init() {
        loadConfig(force: true)
        draft.load(from: config)
        showingSettings = config == nil
        startPolling(refreshFirst: true)
    }

    private func startPolling(refreshFirst: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var refreshNow = refreshFirst
            while !Task.isCancelled {
                if refreshNow { await self?.refresh() }
                refreshNow = true
                let visible = self?.isVisible ?? false
                let seconds: UInt64 = visible ? 4 : 30
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    // MARK: Derived state

    var isPlaying: Bool { status.state == .playing }
    var isMuted: Bool { status.muted == true }
    var iconBadge: MenuBarIcon.Badge { MenuBarIcon.badge(state: status.state, muted: isMuted) }

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
        case .playing: return isMuted ? "Playing, muted" : "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    // MARK: Config file

    /// Reads the config file again when it changed since the last read (or always with `force`).
    /// An automatic reload that fails (a half-saved hand edit) keeps the last good config.
    func loadConfig(force: Bool = false) {
        let stamp = ConfigFile.modificationDate(configURL)
        if configLoaded && !force && stamp == configStamp { return }
        configLoaded = true
        configStamp = stamp
        do {
            let loaded = try ConfigFile.load(configURL)
            configError = nil
            resetBackend()
            config = loaded
        } catch {
            configError = error.localizedDescription
            if force || config == nil {
                resetBackend()
                config = nil
                showingSettings = true
            }
        }
    }

    private func resetBackend() {
        epoch += 1
        backend = nil
        stations = []
        stationsLoaded = false
        stationsError = nil
        stationsRetryAt = .distantPast
        error = nil
        testMessage = nil
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

    // MARK: Settings editor

    func editSettings() {
        draft.load(from: config)
        browse = nil
        saveError = nil
        cancelTest()
        showingSettings = true
    }

    func closeEditor() {
        browse = nil
        cancelTest()
        showingSettings = false
    }

    private func cancelTest() {
        testToken += 1
        browseToken += 1
        countToken += 1
        testing = false
        testMessage = nil
    }

    func saveDraft() {
        do {
            let cfg = try draft.makeConfig()
            try ConfigFile.write(cfg, to: configURL)
            cancelTest()
            saveError = nil
            browse = nil
            loadConfig(force: true)
            showingSettings = false
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Tests the panel's draft as typed, without saving it.
    func testDraft() {
        testToken += 1
        let mine = testToken
        testing = true
        testMessage = nil
        Task {
            let ok: Bool
            let message: String
            do {
                let b = try draft.makeConfig().makeBackend()
                let st = try await b.status()
                let list = try await b.stations()
                ok = true
                message = "Connected: \(st.state.rawValue), \(list.count) stations."
            } catch {
                ok = false
                message = error.localizedDescription
            }
            guard mine == testToken else { return }
            testOK = ok
            testMessage = message
            testing = false
        }
    }

    // MARK: Playlist browser

    func openBrowse() {
        browseToken += 1
        countToken += 1
        let mine = browseToken
        var state = PlaylistBrowser()
        state.loading = true
        browse = state
        Task {
            var items: [PlaylistRef] = []
            var failure: String?
            do {
                let cfg = try draft.makeConfig(requirePlaylist: false)
                items = try await cfg.makeBackend(requirePlaylist: false).playlists()
            } catch {
                failure = error.localizedDescription
            }
            guard mine == browseToken else { return }
            if failure == nil {
                browse?.items = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            browse?.error = failure
            browse?.loading = false
        }
    }

    var browseFiltered: [PlaylistRef] {
        guard let b = browse, !b.filter.isEmpty else { return browse?.items ?? [] }
        return b.items.filter {
            $0.name.localizedCaseInsensitiveContains(b.filter) || $0.uri.localizedCaseInsensitiveContains(b.filter)
        }
    }

    func choosePlaylist(_ p: PlaylistRef) {
        let duplicate = (browse?.items ?? []).filter {
            $0.name.caseInsensitiveCompare(p.name) == .orderedSame
        }.count > 1
        draft.playlist = duplicate ? p.uri : p.name
        browse?.count = nil
        browse?.counting = true
        countToken += 1
        let mine = countToken
        Task {
            var count: Int?
            var failure: String?
            do {
                let cfg = try draft.makeConfig(requirePlaylist: false)
                count = try await cfg.makeBackend(requirePlaylist: false).stations().count
            } catch {
                failure = error.localizedDescription
            }
            guard mine == countToken else { return }
            if let failure { browse?.error = failure } else { browse?.count = count }
            browse?.counting = false
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

    /// Queues `op` after everything queued before it and returns its task.
    @discardableResult
    private func enqueue(_ op: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            _ = await previous?.value
            await op()
        }
        tail = task
        return task
    }

    /// One poll at most waits in the chain: opening the panel several times does not stack them.
    func refresh() async {
        if pollQueued, let op = pollOp {
            await op.value
            return
        }
        pollQueued = true
        let op = enqueue {
            self.pollQueued = false
            guard !Task.isCancelled else { return }
            await self.refreshNow()
        }
        pollOp = op
        await op.value
    }

    /// One poll. Every `@Published` write is guarded, so an unchanged server redraws nothing.
    private func refreshNow() async {
        loadConfig()
        guard config != nil else { return }
        let started = epoch
        do {
            let b = try currentBackend()
            let s = try await b.status()
            guard started == epoch else { return }
            if status != s { status = s }
            if !isEditingVolume, Date() >= volumeHoldUntil, let v = s.volume { volume = Double(v) }
            if error != nil { error = nil }
            if !stationsLoaded, Date() >= stationsRetryAt {
                do {
                    let list = try await b.stations()
                    guard started == epoch else { return }
                    // Duplicate URIs would give duplicate grid identities.
                    var seen = Set<String>()
                    stations = list.filter { seen.insert($0.uri).inserted }
                    stationsLoaded = true
                    stationsError = nil
                } catch {
                    guard started == epoch else { return }
                    // A wrong playlist is not refetched on every poll.
                    stationsRetryAt = Date().addingTimeInterval(30)
                    let msg = error.localizedDescription
                    if stationsError != msg { stationsError = msg }
                }
            }
        } catch {
            // A poll cut short by an action is not an error worth showing.
            guard started == epoch, !Task.isCancelled else { return }
            let msg = error.localizedDescription
            if self.error != msg { self.error = msg }
        }
    }

    func reloadStations() async {
        resetBackend()
        await refresh()
    }

    private func run(_ body: @escaping @MainActor @Sendable (PlayerBackend) async throws -> Void) async {
        epoch += 1
        pollOp?.cancel()        // its result would be dropped anyway; do not wait for it
        pendingActions += 1
        if !busy { busy = true }
        await enqueue {
            do {
                try await body(try self.currentBackend())
                if self.error != nil { self.error = nil }
            } catch {
                self.error = error.localizedDescription
            }
            // Only the last queued action reads the state back.
            if self.pendingActions == 1 { await self.refreshNow() }
        }.value
        pendingActions -= 1
        if pendingActions == 0 { busy = false }
    }

    // MARK: Actions

    /// Pressing play means "I want to hear it": a muted server is unmuted first.
    func play(_ s: Station) async {
        status.currentURI = s.uri
        playIntent += 1
        let mine = playIntent
        let unmute = isMuted
        await run { b in
            guard mine == self.playIntent else { return }
            if unmute { try await b.setMute(false) }
            try await b.play(s)
        }
    }

    func toggleMute() async {
        guard let muted = status.muted else { return }
        status.muted = !muted
        await run { try await $0.setMute(!muted) }
    }

    func togglePlay() async {
        switch status.state {
        case .playing: await run { try await $0.pause() }
        case .paused:
            let unmute = isMuted
            await run { b in
                if unmute { try await b.setMute(false) }
                try await b.resume()
            }
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
        holdVolume()
        volumeIntent += 1
        let mine = volumeIntent
        await run { b in
            guard mine == self.volumeIntent else { return }
            try await b.setVolume(clamped)
        }
    }

    /// Slider drag starts: a -/+ click still waiting must not move the thumb mid-drag.
    func beginVolumeDrag() {
        isEditingVolume = true
        volumeSend?.cancel()
        volumeSend = nil
    }

    /// Slider released: hold the value and invalidate polls in flight before the task runs,
    /// so no poll lands in between and snaps the thumb back.
    func commitVolume(_ v: Int) {
        isEditingVolume = false
        volume = Double(max(0, min(100, v)))
        holdVolume()
        epoch += 1
        Task { await setVolume(v) }
    }

    /// Step of the -/+ buttons and the arrow keys.
    static let volumeStep = 5

    private func holdVolume() { volumeHoldUntil = Date().addingTimeInterval(1.5) }

    /// -/+ buttons: the number moves at once, the server gets one call once the clicks
    /// (or a held button) pause for 250 ms, instead of one request per step.
    func nudgeVolume(_ delta: Int) {
        guard status.volume != nil else { return }
        let target = max(0, min(100, Int(volume.rounded()) + delta))
        volume = Double(target)
        holdVolume()
        volumeSend?.cancel()
        volumeSend = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.setVolume(target)
        }
    }
}
