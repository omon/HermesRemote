import Citadel
import Crypto
import Foundation
import NIO
import NIOSSH

@MainActor
final class SSHService: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, awaitingHostApproval, connected, failed(String)

        var label: String {
            switch self {
            case .disconnected: "未接続"
            case .connecting: "接続中…"
            case .awaitingHostApproval: "ホスト鍵の確認待ち"
            case .connected: "接続済み"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var pendingFingerprint: String?
    @Published private(set) var title = "Hermes"
    @Published private(set) var isInputReady = false

    private(set) var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?
    private var terminalFeed: (@MainActor @Sendable ([UInt8]) -> Void)?
    private var terminalFocus: (@MainActor @Sendable () -> Void)?
    private var terminalDismissKeyboard: (@MainActor @Sendable () -> Void)?
    private var pendingHostKey: HostKeyValidator.Candidate?
    private var lastSettings: AppSettings?

    func setTerminalFeed(_ feed: @escaping @MainActor @Sendable ([UInt8]) -> Void) {
        terminalFeed = feed
    }

    func clearTerminalFeed() { terminalFeed = nil }

    func setTerminalFocus(_ focus: @escaping @MainActor @Sendable () -> Void) {
        terminalFocus = focus
    }

    func clearTerminalFocus() { terminalFocus = nil }

    func focusTerminal() { terminalFocus?() }

    func setTerminalDismissKeyboard(_ dismiss: @escaping @MainActor @Sendable () -> Void) {
        terminalDismissKeyboard = dismiss
    }

    func clearTerminalDismissKeyboard() { terminalDismissKeyboard = nil }

    func dismissTerminalKeyboard() { terminalDismissKeyboard?() }

    func updateTerminalTitle(_ value: String) {
        title = value.isEmpty ? "Hermes" : value
    }

    func connect(settings: AppSettings) {
        guard settings.isConnectionConfigured else {
            state = .failed(HermesRemoteError.missingConfiguration.localizedDescription)
            return
        }
        lastSettings = settings
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in await self?.runSession(settings: settings) }
    }

    func disconnect() {
        sessionTask?.cancel()
        sessionTask = nil
        let current = client
        client = nil
        writer = nil
        isInputReady = false
        state = .disconnected
        Task { try? await current?.close() }
    }

    func approvePendingHostKey() {
        guard let pendingHostKey, let settings = lastSettings else { return }
        do {
            try KeychainStore.shared.set(pendingHostKey.openSSHKey,
                account: KeychainStore.Account.hostKey(host: settings.host.lowercased(), port: settings.port))
            self.pendingHostKey = nil
            pendingFingerprint = nil
            connect(settings: settings)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func forgetHostKey(settings: AppSettings) throws {
        try KeychainStore.shared.delete(account: KeychainStore.Account.hostKey(
            host: settings.host.lowercased(), port: settings.port))
    }

    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        guard let writer else {
            state = .failed("Terminalの入力チャンネルが準備できていません。再接続してください。")
            isInputReady = false
            return
        }
        Task {
            do {
                try await writer.write(ByteBuffer(bytes: bytes))
            } catch {
                await MainActor.run {
                    self.isInputReady = false
                    self.state = .failed("Terminalへの入力送信に失敗しました: \(error.localizedDescription)")
                }
            }
        }
    }

    func resize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        guard let writer, columns > 0, rows > 0 else { return }
        Task { try? await writer.changeSize(cols: columns, rows: rows,
                                             pixelWidth: pixelWidth, pixelHeight: pixelHeight) }
    }

    private func runSession(settings: AppSettings) async {
        state = .connecting
        pendingFingerprint = nil
        var attemptedValidator: HostKeyValidator?
        do {
            let startupCommand = settings.startupCommand
            let auth: SSHAuthenticationMethod
            switch settings.authenticationKind {
            case .password:
                guard let password = try KeychainStore.shared.string(account: KeychainStore.Account.password),
                      !password.isEmpty else {
                    throw HermesRemoteError.missingPassword
                }
                auth = .passwordBased(username: settings.username, password: password)
            case .privateKey:
                guard let keyData = try KeychainStore.shared.data(account: KeychainStore.Account.privateKey),
                      let keyText = String(data: keyData, encoding: .utf8) else {
                    throw HermesRemoteError.missingPrivateKey
                }
                let passphrase = try KeychainStore.shared.data(account: KeychainStore.Account.keyPassphrase)
                auth = try Self.authentication(username: settings.username, key: keyText, passphrase: passphrase)
            }
            let account = KeychainStore.Account.hostKey(host: settings.host.lowercased(), port: settings.port)
            let validator = HostKeyValidator(knownKey: try KeychainStore.shared.string(account: account))
            attemptedValidator = validator
            let connected = try await SSHClient.connect(
                host: settings.host, port: settings.port, authenticationMethod: auth,
                hostKeyValidator: .custom(validator), reconnect: .never
            )
            client = connected

            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true, term: "xterm-256color", terminalCharacterWidth: 80,
                terminalRowHeight: 24, terminalPixelWidth: 0, terminalPixelHeight: 0,
                terminalModes: .init([.ECHO: 1])
            )
            try await connected.withPTY(request) { [weak self] inbound, outbound in
                await MainActor.run {
                    self?.writer = outbound
                    self?.isInputReady = true
                    self?.state = .connected
                }
                if !startupCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await outbound.write(ByteBuffer(string: startupCommand + "\n"))
                }
                for try await output in inbound {
                    switch output {
                    case .stdout(var buffer), .stderr(var buffer):
                        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
                        await MainActor.run { self?.terminalFeed?(bytes) }
                    }
                }
            }
            if !Task.isCancelled { state = .disconnected }
        } catch {
            if let candidate = attemptedValidator?.candidate {
                pendingHostKey = candidate
                pendingFingerprint = candidate.fingerprint
                state = .awaitingHostApproval
            } else if !Task.isCancelled {
                state = .failed(Self.friendlyMessage(error))
            }
        }
        writer = nil
        isInputReady = false
        client = nil
    }

    private static func authentication(username: String, key: String, passphrase: Data?) throws -> SSHAuthenticationMethod {
        switch try SSHKeyDetection.detectPrivateKeyType(from: key) {
        case .ed25519:
            return .ed25519(username: username,
                privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase))
        case .rsa:
            return .rsa(username: username,
                privateKey: try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase))
        default:
            throw HermesRemoteError.unsupportedPrivateKey
        }
    }

    private static func friendlyMessage(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("authentication") {
            return "認証に失敗しました。Usernameと選択中の認証情報を確認してください。"
        }
        if text.localizedCaseInsensitiveContains("host") && text.localizedCaseInsensitiveContains("key") { return text }
        if text.localizedCaseInsensitiveContains("timed out") { return "接続がタイムアウトしました。VPN/Tailscale経路を確認してください。" }
        return "SSH接続に失敗しました: \(text)"
    }
}
