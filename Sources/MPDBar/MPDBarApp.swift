import MPDBarCore
import SwiftUI

@main
struct MPDBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(model.iconBadge))
                .renderingMode(.template)
                .accessibilityLabel("MPD Bar, \(model.subtitle)")
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        Group {
            if m.showingSettings {
                SettingsView()
            } else {
                PlayerView()
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { m.isVisible = true }
        .onDisappear { m.isVisible = false }
    }
}
