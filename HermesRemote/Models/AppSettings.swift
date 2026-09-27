import Foundation

enum SSHAuthenticationKind: String, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }
    var label: String {
        switch self {
        case .password: "パスワード"
        case .privateKey: "秘密鍵"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let host = "ssh.host"
        static let port = "ssh.port"
        static let username = "ssh.username"
        static let authenticationKind = "ssh.authenticationKind"
        static let startupCommand = "hermes.startupCommand"
        static let tmuxSession = "hermes.tmuxSession"
        static let hermesDirectory = "remote.hermesDirectory"
        static let tipsDirectory = "remote.tipsDirectory"
        static let exportDirectory = "local.exportDirectory"
        static let tipsLocalDirectory = "local.tipsDirectory"
    }

    @Published var host: String { didSet { defaults.set(host, forKey: Key.host) } }
    @Published var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    @Published var username: String { didSet { defaults.set(username, forKey: Key.username) } }
    @Published var authenticationKind: SSHAuthenticationKind {
        didSet { defaults.set(authenticationKind.rawValue, forKey: Key.authenticationKind) }
    }
    @Published var startupCommand: String { didSet { defaults.set(startupCommand, forKey: Key.startupCommand) } }
    @Published var tmuxSession: String {
        didSet {
            defaults.set(tmuxSession, forKey: Key.tmuxSession)
            if startupCommand == Self.tmuxCommand(session: oldValue) {
                startupCommand = Self.tmuxCommand(session: tmuxSession)
            }
        }
    }
    @Published var hermesDirectory: String { didSet { defaults.set(hermesDirectory, forKey: Key.hermesDirectory) } }
    @Published var tipsDirectory: String { didSet { defaults.set(tipsDirectory, forKey: Key.tipsDirectory) } }
    @Published var exportDirectory: String { didSet { defaults.set(exportDirectory, forKey: Key.exportDirectory) } }
    @Published var tipsLocalDirectory: String { didSet { defaults.set(tipsLocalDirectory, forKey: Key.tipsLocalDirectory) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        host = defaults.string(forKey: Key.host) ?? ""
        port = defaults.object(forKey: Key.port) as? Int ?? 22
        username = defaults.string(forKey: Key.username) ?? ""
        authenticationKind = SSHAuthenticationKind(
            rawValue: defaults.string(forKey: Key.authenticationKind) ?? ""
        ) ?? .password
        startupCommand = defaults.string(forKey: Key.startupCommand) ?? "tmux new-session -A -s hermes"
        tmuxSession = defaults.string(forKey: Key.tmuxSession) ?? "hermes"
        hermesDirectory = defaults.string(forKey: Key.hermesDirectory) ?? "~/hermes-share"
        tipsDirectory = defaults.string(forKey: Key.tipsDirectory) ?? "~/tips"
        exportDirectory = defaults.string(forKey: Key.exportDirectory) ?? "exports"
        tipsLocalDirectory = defaults.string(forKey: Key.tipsLocalDirectory) ?? "tips"
    }

    var isConnectionConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...65535).contains(port)
    }

    private static func tmuxCommand(session: String) -> String {
        "tmux new-session -A -s \(session)"
    }
}
