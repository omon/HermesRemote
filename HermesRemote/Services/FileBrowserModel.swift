import Citadel
import Foundation
import NIO

@MainActor
final class FileBrowserModel: ObservableObject {
    @Published private(set) var remoteItems: [RemoteItem] = []
    @Published private(set) var currentRemotePath = ""
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var exportURLs: [URL] = []
    @Published var previewURL: URL?

    func list(path: String, client: SSHClient?) async {
        guard let client else { errorMessage = HermesRemoteError.notConnected.localizedDescription; return }
        isWorking = true; defer { isWorking = false }
        do {
            remoteItems = try await client.withSFTP { sftp in
                let resolved = try await Self.resolve(path: path, sftp: sftp)
                let pages = try await sftp.listDirectory(atPath: resolved)
                return pages.flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }.map { entry in
                    let permissions = entry.attributes.permissions ?? 0
                    let isDirectory = (permissions & 0o170000) == 0o040000 || entry.longname.first == "d"
                    return RemoteItem(path: Self.join(resolved, entry.filename), name: entry.filename,
                                      size: entry.attributes.size,
                                      modifiedAt: entry.attributes.accessModificationTime?.modificationTime,
                                      isDirectory: isDirectory)
                }.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
            currentRemotePath = path
        } catch { errorMessage = "SFTP一覧取得に失敗しました: \(error.localizedDescription)" }
    }

    func download(_ item: RemoteItem, settings: AppSettings, client: SSHClient?, exportAfter: Bool = false) async {
        guard let client else { errorMessage = HermesRemoteError.notConnected.localizedDescription; return }
        isWorking = true; defer { isWorking = false }
        do {
            let root = try LocalFileStore.shared.directory(named: settings.exportDirectory)
            let local = try LocalFileStore.shared.safeDestination(root: root, relativeComponents: [item.name])
            try await client.withSFTP { sftp in
                if item.isDirectory {
                    try await Self.downloadDirectory(sftp: sftp, remote: item.path, local: local)
                } else {
                    try await Self.downloadFile(sftp: sftp, remote: item.path, local: local)
                }
            }
            if exportAfter { exportURLs = [local] }
        } catch { errorMessage = "Downloadに失敗しました: \(error.localizedDescription)" }
    }

    func downloadTips(settings: AppSettings, client: SSHClient?, exportAfter: Bool = false) async {
        guard let client else { errorMessage = HermesRemoteError.notConnected.localizedDescription; return }
        isWorking = true; defer { isWorking = false }
        do {
            let local = try LocalFileStore.shared.directory(named: settings.tipsLocalDirectory)
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            try await client.withSFTP { sftp in
                let remote = try await Self.resolve(path: settings.tipsDirectory, sftp: sftp)
                try await Self.downloadDirectoryContents(sftp: sftp, remote: remote, local: local)
            }
            if exportAfter { exportURLs = [local] }
        } catch { errorMessage = "Tips取得に失敗しました: \(error.localizedDescription)" }
    }

    func preview(_ item: RemoteItem, client: SSHClient?) async {
        guard !item.isDirectory else { return }
        guard let client else { errorMessage = HermesRemoteError.notConnected.localizedDescription; return }
        guard (item.size ?? 0) <= 5 * 1_024 * 1_024 else {
            errorMessage = "Remote Previewは5 MB以下のファイルに制限しています。Downloadして確認してください。"
            return
        }
        isWorking = true; defer { isWorking = false }
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("HermesRemotePreview", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let local = try LocalFileStore.shared.safeDestination(root: root, relativeComponents: [item.name])
            try await client.withSFTP { sftp in try await Self.downloadFile(sftp: sftp, remote: item.path, local: local) }
            previewURL = local
        } catch { errorMessage = "Preview取得に失敗しました: \(error.localizedDescription)" }
    }

    nonisolated private static func downloadDirectory(sftp: SFTPClient, remote: String, local: URL) async throws {
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try await downloadDirectoryContents(sftp: sftp, remote: remote, local: local)
    }

    nonisolated private static func downloadDirectoryContents(sftp: SFTPClient, remote: String, local: URL) async throws {
        let pages = try await sftp.listDirectory(atPath: remote)
        for entry in pages.flatMap(\.components) where entry.filename != "." && entry.filename != ".." {
            guard LocalFileStore.isSafeComponent(entry.filename) else { throw HermesRemoteError.invalidRemotePath }
            let remoteChild = join(remote, entry.filename)
            let localChild = try LocalFileStore.shared.safeDestination(root: local, relativeComponents: [entry.filename])
            let permissions = entry.attributes.permissions ?? 0
            let isDirectory = (permissions & 0o170000) == 0o040000 || entry.longname.first == "d"
            if isDirectory {
                try await downloadDirectory(sftp: sftp, remote: remoteChild, local: localChild)
            } else {
                try await downloadFile(sftp: sftp, remote: remoteChild, local: localChild)
            }
        }
    }

    nonisolated private static func downloadFile(sftp: SFTPClient, remote: String, local: URL) async throws {
        var buffer = try await sftp.withFile(filePath: remote, flags: .read) { try await $0.readAll() }
        let data = buffer.readData(length: buffer.readableBytes) ?? Data()
        try LocalFileStore.shared.write(data, to: local)
    }

    nonisolated private static func resolve(path: String, sftp: SFTPClient) async throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { throw HermesRemoteError.invalidRemotePath }
        if trimmed == "~" { return try await sftp.getRealPath(atPath: ".") }
        if trimmed.hasPrefix("~/") {
            return join(try await sftp.getRealPath(atPath: "."), String(trimmed.dropFirst(2)))
        }
        return try await sftp.getRealPath(atPath: trimmed)
    }

    nonisolated private static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }
}
