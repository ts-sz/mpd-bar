import MPDBarCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    @State private var draft = PlayerSettings.load()
    @State private var cfClientID = Keychain.read(Keychain.cfClientID) ?? ""
    @State private var cfClientSecret = ""
    @State private var mpdPassword = ""
    @State private var testMessage: String?
    @State private var testOK = false
    @State private var testing = false

    private let hasCFSecret = Keychain.read(Keychain.cfClientSecret) != nil
    private let hasMPDPassword = Keychain.read(Keychain.mpdPassword) != nil

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

            Picker("", selection: $draft.backend) {
                ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if draft.backend == .mopidy {
                field("Server URL") {
                    TextField("http://host:6680", text: $draft.mopidyURL)
                }
                Picker("", selection: $draft.mopidyAuth) {
                    ForEach(MopidyAuth.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if draft.mopidyAuth == .cloudflareAccess {
                    field("Client ID") {
                        TextField("xxxxxxxx.access", text: $cfClientID)
                    }
                    field("Client Secret") {
                        SecureField(hasCFSecret ? "Saved in Keychain" : "Paste the secret", text: $cfClientSecret)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    field("Host") { TextField("localhost", text: $draft.mpdHost) }
                    field("Port") { TextField("6600", value: $draft.mpdPort, format: .number.grouping(.never)) }
                        .frame(width: 70)
                }
                field("Password (optional)") {
                    SecureField(hasMPDPassword ? "Saved in Keychain" : "None", text: $mpdPassword)
                }
            }

            field("Playlist") {
                TextField("Playlist name", text: $draft.playlist)
            }

            if let msg = testMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(testOK ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(testing ? "Testing..." : "Test") { Task { await test() } }
                    .disabled(testing || !draft.isConfigured)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isConfigured)
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

    /// Typed values win; empty fields fall back to what the Keychain already holds.
    private func draftCredentials() -> Credentials {
        let saved = Credentials.fromKeychain()
        let id = cfClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = cfClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = mpdPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return Credentials(cfClientID: id.isEmpty ? saved.cfClientID : id,
                           cfClientSecret: secret.isEmpty ? saved.cfClientSecret : secret,
                           mpdPassword: pw.isEmpty ? saved.mpdPassword : pw)
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let backend = try BackendFactory.make(draft, credentials: draftCredentials())
            let st = try await backend.status()
            let stations = try await backend.stations()
            testOK = true
            testMessage = "Connected: \(st.state.rawValue), \(stations.count) stations."
        } catch {
            testOK = false
            testMessage = error.localizedDescription
        }
    }

    private func save() {
        let id = cfClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = cfClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = mpdPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { Keychain.write(Keychain.cfClientID, id) }
        if !secret.isEmpty { Keychain.write(Keychain.cfClientSecret, secret) }
        if !pw.isEmpty { Keychain.write(Keychain.mpdPassword, pw) }
        cfClientSecret = ""
        mpdPassword = ""
        m.applySettings(draft)
    }
}
