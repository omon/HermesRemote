import SwiftUI

@main
struct HermesRemoteApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var ssh = SSHService()
    @StateObject private var files = FileBrowserModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(ssh)
                .environmentObject(files)
                .task { try? LocalFileStore.shared.prepareDirectories(settings: settings) }
        }
    }
}
