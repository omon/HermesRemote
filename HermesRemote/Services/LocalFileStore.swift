import Foundation

final class LocalFileStore: @unchecked Sendable {
    static let shared = LocalFileStore()
    private let fm = FileManager.default

    var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    @MainActor
    func prepareDirectories(settings: AppSettings) throws {
        try fm.createDirectory(at: try directory(named: settings.exportDirectory),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: try directory(named: settings.tipsLocalDirectory),
                               withIntermediateDirectories: true)
    }

    func directory(named name: String) throws -> URL {
        guard Self.isSafeComponent(name) else { throw HermesRemoteError.invalidLocalName }
        let url = documentsURL.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func items(at directory: URL) throws -> [LocalItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                          options: [.skipsHiddenFiles]).map { url in
            let values = try url.resourceValues(forKeys: keys)
            return LocalItem(url: url, isDirectory: values.isDirectory ?? false,
                             size: values.fileSize.map(UInt64.init), modifiedAt: values.contentModificationDate)
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func safeDestination(root: URL, relativeComponents: [String]) throws -> URL {
        guard relativeComponents.allSatisfy(Self.isSafeComponent) else { throw HermesRemoteError.invalidRemotePath }
        let destination = relativeComponents.reduce(root) { $0.appendingPathComponent($1) }
        let rootPath = root.standardizedFileURL.path + "/"
        guard destination.standardizedFileURL.path.hasPrefix(rootPath) else { throw HermesRemoteError.invalidRemotePath }
        return destination
    }

    func write(_ data: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func delete(_ url: URL) throws { try fm.removeItem(at: url) }

    func rename(_ url: URL, to name: String) throws -> URL {
        guard Self.isSafeComponent(name) else { throw HermesRemoteError.invalidLocalName }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        try fm.moveItem(at: url, to: target)
        return target
    }

    static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        !value.contains("/") && !value.contains(":") && !value.contains("\0")
    }
}
