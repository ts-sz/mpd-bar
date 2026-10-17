import MPDBarCore
import SwiftUI

/// Settings = a draft editor over the config file. Save writes the file (mode 600, atomic) and
/// the app reloads from disk, so the panel is never a second store. The playlist list comes
/// from the server, with the draft's own connection settings.
struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { m.closeEditor() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
            }

            Editor(m: m, draft: m.draft)
        }
    }
}

private struct Editor: View {
    @ObservedObject var m: AppModel
    @ObservedObject var draft: ConfigDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            fileSection
            connectionSection
            playlistSection

            if let msg = m.testMessage { message(msg, ok: m.testOK) }
            if let err = m.saveError { message(err, ok: false) }

            HStack {
                Button(m.testing ? "Testing..." : "Test") { m.testDraft() }
                    .disabled(m.testing)
                Spacer()
                Button("Save") { m.saveDraft() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)

            Text("Saving writes the config file (mode 600) and reloads it. Hand edits stay possible.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sections

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("CONFIG FILE")
            Text(m.configPath)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            if let c = m.config {
                Label(c.summary, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let e = m.configError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if m.configExists {
                HStack(spacing: 8) {
                    Button("Open") { m.openConfig() }
                    Button("Reveal") { m.revealConfig() }
                    Button("Reload") { Task { await m.reloadConfig() } }
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CONNECTION")
            Picker("", selection: $draft.mode) {
                ForEach(ConnectionMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch draft.mode {
            case .cloudflare:
                field("Server URL") { TextField("https://music.example.com", text: $draft.serverURL) }
                field("Client ID") { TextField("xxxxxxxx.access", text: $draft.clientID) }
                field("Client Secret") { SecureField("Service token secret", text: $draft.clientSecret) }
            case .mopidyDirect:
                field("Server URL") { TextField("http://music.local:6680", text: $draft.serverURL) }
            case .mpd:
                HStack(alignment: .bottom, spacing: 8) {
                    field("Host") { TextField("localhost", text: $draft.mpdHost) }
                    field("Port") { TextField("6600", text: $draft.mpdPort).frame(width: 64) }
                }
                field("Password (optional)") { SecureField("None", text: $draft.mpdPassword) }
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("PLAYLIST")
            HStack(spacing: 8) {
                TextField("radios", text: $draft.playlist)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button(m.browse == nil ? "Browse..." : "Hide") {
                    if m.browse == nil { m.openBrowse() } else { m.browse = nil }
                }
                .controlSize(.small)
            }
            if let b = m.browse {
                browser(b)
            }
        }
    }

    @ViewBuilder
    private func browser(_ b: PlaylistBrowser) -> some View {
        if b.loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Fetching playlists...").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else if let e = b.error {
            Text(e)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Filter", text: Binding(
                    get: { m.browse?.filter ?? "" },
                    set: { m.browse?.filter = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                let rows = m.browseFiltered
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if rows.isEmpty {
                            Text("No match.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(rows, id: \.self) { p in
                            Button { m.choosePlaylist(p) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name)
                                        .font(.system(size: 12, weight: p.name.caseInsensitiveCompare(draft.playlist) == .orderedSame ? .semibold : .regular))
                                        .lineLimit(1)
                                    if p.uri != p.name {
                                        Text(p.uri)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(p.name.caseInsensitiveCompare(draft.playlist) == .orderedSame || p.uri == draft.playlist
                                      ? Color.accentColor.opacity(0.15) : Color.clear))
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 180)
                if let c = b.count {
                    Text("\(c) \(c == 1 ? "track" : "tracks")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if b.counting {
                    Text("Counting tracks...")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func field<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(name.uppercased())
            content()
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
    }

    private func message(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(ok ? Color.green : Color.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}
