import SwiftUI
import UIKit

struct RootView: View {
    private enum Tab: Hashable { case terminal, files, settings }
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: Tab = .terminal

    var body: some View {
        TabView(selection: $selection) {
            TerminalScreen()
                .tabItem { Label("Terminal", systemImage: "terminal") }
                .tag(Tab.terminal)
            FilesScreen()
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(Tab.files)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: selection) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            if !settings.isConnectionConfigured {
                selection = .settings
            }
        }
    }
}
