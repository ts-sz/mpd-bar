import MPDBarCore
import SwiftUI

/// The settings live in a JSON file; this panel shows where it is, whether it parses, and tests it.
/// All state lives in `AppModel`: the view never mutates its own stored properties.
struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                if m.config != nil {
                    Button { m.showingSettings = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CONFIG FILE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(m.configPath)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

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

            HStack(spacing: 8) {
                if m.configExists {
                    Button("Open") { m.openConfig() }
                    Button("Reveal") { m.revealConfig() }
                    Button("Reload") { Task { await m.reloadConfig() } }
                } else {
                    Button("Create config file") { m.createConfig() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button(m.testing ? "Testing..." : "Test") { Task { await m.test() } }
                    .disabled(m.testing || m.config == nil)
            }
            .controlSize(.small)

            if let msg = m.testMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(m.testOK ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Edit the file and save: the app reloads it. It holds your secrets, so it stays private to your user (mode 600).")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
