import MPDBarCore
import SwiftUI

/// Editable copy of the settings and the secrets being typed. A reference type, so the view
/// never mutates its own stored properties from methods (newer SwiftUI toolchains reject that).
@MainActor
final class SettingsForm: ObservableObject {
    @Published var draft = PlayerSettings.load()
    @Published var cfClientID = Keychain.read(Keychain.cfClientID) ?? ""
    @Published var cfClientSecret = ""
    @Published var mpdPassword = ""
    @Published var testMessage: String?
    @Published var testOK = false
    @Published var testing = false

    let hasCFSecret = Keychain.read(Keychain.cfClientSecret) != nil
    let hasMPDPassword = Keychain.read(Keychain.mpdPassword) != nil

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Typed values win; empty fields fall back to what the Keychain already holds.
    func credentials() -> Credentials {
        let saved = Credentials.fromKeychain()
        let id = trimmed(cfClientID)
        let secret = trimmed(cfClientSecret)
        let pw = trimmed(mpdPassword)
        return Credentials(cfClientID: id.isEmpty ? saved.cfClientID : id,
                           cfClientSecret: secret.isEmpty ? saved.cfClientSecret : secret,
                           mpdPassword: pw.isEmpty ? saved.mpdPassword : pw)
    }

    func test() async {
        testing = true
        defer { testing = false }
        do {
            let backend = try BackendFactory.make(draft, credentials: credentials())
            let st = try await backend.status()
            let stations = try await backend.stations()
            testOK = true
            testMessage = "Connected: \(st.state.rawValue), \(stations.count) stations."
        } catch {
            testOK = false
            testMessage = error.localizedDescription
        }
    }

    /// Writes typed secrets to the Keychain, clears them from memory, returns the settings to apply.
    func commit() -> PlayerSettings {
        let id = trimmed(cfClientID)
        let secret = trimmed(cfClientSecret)
        let pw = trimmed(mpdPassword)
        if !id.isEmpty { Keychain.write(Keychain.cfClientID, id) }
        if !secret.isEmpty { Keychain.write(Keychain.cfClientSecret, secret) }
        if !pw.isEmpty { Keychain.write(Keychain.mpdPassword, pw) }
        cfClientSecret = ""
        mpdPassword = ""
        return draft
    }
}

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @StateObject private var form = SettingsForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                if m.settings.isConfigured {
                    Button { m.showingSettings = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close")
                }
            }

            Picker("", selection: $form.draft.backend) {
                ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if form.draft.backend == .mopidy {
                field("Server URL") {
                    TextField("http://host:6680", text: $form.draft.mopidyURL)
                }
                Picker("", selection: $form.draft.mopidyAuth) {
                    ForEach(MopidyAuth.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if form.draft.mopidyAuth == .cloudflareAccess {
                    field("Client ID") {
                        TextField("xxxxxxxx.access", text: $form.cfClientID)
                    }
                    field("Client Secret") {
                        SecureField(form.hasCFSecret ? "Saved in Keychain" : "Paste the secret",
                                    text: $form.cfClientSecret)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    field("Host") { TextField("localhost", text: $form.draft.mpdHost) }
                    field("Port") {
                        TextField("6600", value: $form.draft.mpdPort, format: .number.grouping(.never))
                    }
                    .frame(width: 70)
                }
                field("Password (optional)") {
                    SecureField(form.hasMPDPassword ? "Saved in Keychain" : "None", text: $form.mpdPassword)
                }
            }

            field("Playlist") {
                TextField("Playlist name", text: $form.draft.playlist)
            }

            if let msg = form.testMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(form.testOK ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(form.testing ? "Testing..." : "Test") {
                    let f = form
                    Task { await f.test() }
                }
                .disabled(form.testing || !form.draft.isConfigured)
                Spacer()
                Button("Save") { m.applySettings(form.commit()) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!form.draft.isConfigured)
            }
            .controlSize(.small)

            Text("Secrets are stored in your login Keychain.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
    }
}
