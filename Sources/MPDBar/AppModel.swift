import MPDBarCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = PlayerSettings.load()
    @Published var stations: [Station] = []
    @Published var status = PlayerStatus()
    @Published var volume: Double = 0
    @Published var error: String?
    @Published var busy = false
    @Published var showingSettings = false

    var isEditingVolume = false
    var isVisible = false {
        didSet { if isVisible && !oldValue { Task { await refresh() } } }
    }

    private var backend: PlayerBackend?
    private var pollTask: Task<Void, Never>?

    init() {
        showingSettings = !settings.isConfigured
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

    // MARK: Backend

    func applySettings(_ new: PlayerSettings) {
        new.save()
        settings = new
        backend = nil
        stations = []
        error = nil
        showingSettings = false
        Task { await refresh() }
    }

    private func currentBackend() throws -> PlayerBackend {
        if let b = backend { return b }
        let b = try BackendFactory.make(settings, credentials: .fromKeychain())
        backend = b
        return b
    }

    func refresh() async {
        guard settings.isConfigured else { return }
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
