import AppKit
import MPDBarCore
import SwiftUI

/// Hover flag held by reference, so no view mutates its own stored state.
@MainActor
final class HoverState: ObservableObject {
    @Published var on = false
}

struct TransportButton: View {
    let symbol: String
    var primary = false
    var help = ""
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 17 : 13, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .frame(width: primary ? 44 : 34, height: primary ? 44 : 34)
                .background(
                    Circle().fill(primary ? Color.accentColor : Color.primary.opacity(hover.on ? 0.10 : 0.0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { [hover] inside in hover.on = inside }
        .help(help)
    }
}

struct StationButton: View {
    let station: Station
    let active: Bool
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 5, height: 5)
                Text(station.name)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(hover.on ? 0.09 : 0.045))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { [hover] inside in hover.on = inside }
        .help(station.name)
    }
}

struct PlayerView: View {
    @EnvironmentObject var m: AppModel
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Now playing
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                    Image(systemName: m.isPlaying ? "dot.radiowaves.left.and.right" : "radio")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.headline).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(m.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if m.busy { ProgressView().controlSize(.small) }
            }

            // Transport
            HStack(spacing: 14) {
                Spacer()
                TransportButton(symbol: "backward.fill", help: "Previous station") { Task { await m.step(-1) } }
                TransportButton(symbol: "stop.fill", help: "Stop") { Task { await m.stop() } }
                TransportButton(symbol: m.isPlaying ? "pause.fill" : "play.fill", primary: true, help: "Play / pause") {
                    Task { await m.togglePlay() }
                }
                TransportButton(symbol: "forward.fill", help: "Next station") { Task { await m.step(1) } }
                Spacer()
            }

            // Volume
            HStack(spacing: 8) {
                Button { Task { await m.setVolume(Int(m.volume) - 5) } } label: {
                    Image(systemName: "speaker.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Slider(value: $m.volume, in: 0...100, onEditingChanged: { editing in
                    m.isEditingVolume = editing
                    if !editing { Task { await m.setVolume(Int(m.volume.rounded())) } }
                })
                .controlSize(.small)
                Button { Task { await m.setVolume(Int(m.volume) + 5) } } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Text("\(Int(m.volume.rounded()))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
            .disabled(m.status.volume == nil)

            Divider()

            Text("STATIONS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            if m.stations.isEmpty {
                Text(m.error == nil ? "Loading..." : "No stations.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(m.stations) { s in
                        StationButton(station: s, active: s.uri == m.status.currentURI) {
                            Task { await m.play(s) }
                        }
                    }
                }
            }

            if let e = m.error {
                Text(e)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                Text(m.settings.playlist).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                Button { Task { await m.reloadStations() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload stations")
                Button { m.showingSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
}
