import Foundation

struct RemoteItem: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let size: UInt64?
    let modifiedAt: Date?
    let isDirectory: Bool

    var id: String { path }
}

struct LocalItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: UInt64?
    let modifiedAt: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum HermesRemoteError: LocalizedError {
    case missingConfiguration
    case missingPassword
    case missingPrivateKey
    case unsupportedPrivateKey
    case untrustedHostKey(String)
    case hostKeyMismatch(expected: String, actual: String)
    case invalidRemotePath
    case invalidLocalName
    case remoteFileNotFound(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Host、Port、UsernameをSettingsで設定してください。"
        case .missingPassword: "SSHパスワードをSettingsで保存してください。"
        case .missingPrivateKey: "SSH秘密鍵をSettingsから読み込んでください。"
        case .unsupportedPrivateKey: "対応するOpenSSH秘密鍵（Ed25519またはRSA）ではありません。"
        case .untrustedHostKey(let fingerprint): "初回接続です。ホスト鍵 \(fingerprint) を確認してください。"
        case .hostKeyMismatch(let expected, let actual): "ホスト鍵が変更されています。登録済み: \(expected)、受信: \(actual)"
        case .invalidRemotePath: "安全でないリモートパスです。"
        case .invalidLocalName: "ローカル名に /、:、または .. は使えません。"
        case .remoteFileNotFound(let path): "リモートファイルが見つかりません: \(path)"
        case .notConnected: "先にSSH接続してください。"
        }
    }
}
