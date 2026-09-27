import SwiftUI

struct FilesScreen: View {
    enum Mode: String, CaseIterable { case remote = "Remote", local = "Local" }
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ssh: SSHService
    @EnvironmentObject private var model: FileBrowserModel
    @State private var mode: Mode = .remote
    @State private var showingExporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Location", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding()
                if mode == .remote { remoteView } else { LocalRootView() }
            }
            .navigationTitle("Files")
            .overlay { if model.isWorking { ProgressView().controlSize(.large) } }
            .alert("Files", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
            .sheet(isPresented: $showingExporter) {
                DocumentExporter(urls: model.exportURLs) {
                    showingExporter = false
                    model.exportURLs = []
                }
            }
            .sheet(item: Binding(get: { model.previewURL.map(PreviewURL.init) }, set: { model.previewURL = $0?.url })) {
                QuickLookPreview(url: $0.url)
            }
            .onChange(of: model.exportURLs) { _, urls in if !urls.isEmpty { showingExporter = true } }
        }
    }

    private var remoteView: some View {
        List {
            Section("場所") {
                Button { Task { await model.list(path: settings.hermesDirectory, client: ssh.client) } } label: {
                    Label("Hermes Files", systemImage: "shippingbox")
                }
                Button { Task { await model.list(path: settings.tipsDirectory, client: ssh.client) } } label: {
                    Label("Tips", systemImage: "lightbulb")
                }
                HStack {
                    Button("Download Tips") {
                        Task { await model.downloadTips(settings: settings, client: ssh.client) }
                    }
                    Spacer()
                    Button("Download & Export") {
                        Task { await model.downloadTips(settings: settings, client: ssh.client, exportAfter: true) }
                    }
                }.font(.caption)
            }
            if !model.currentRemotePath.isEmpty {
                Section {
                    if let parent = remoteParent {
                        Button { Task { await model.list(path: parent, client: ssh.client) } } label: {
                            Label("ひとつ上へ", systemImage: "arrow.up")
                        }
                    }
                    ForEach(model.remoteItems) { item in
                        RemoteRow(item: item) {
                            Task { await model.list(path: item.path, client: ssh.client) }
                        } download: { export in
                            Task { await model.download(item, settings: settings, client: ssh.client, exportAfter: export) }
                        } preview: {
                            Task { await model.preview(item, client: ssh.client) }
                        }
                    }
                } header: { Text(model.currentRemotePath) }
            }
        }
        .refreshable {
            let path = model.currentRemotePath.isEmpty ? settings.hermesDirectory : model.currentRemotePath
            await model.list(path: path, client: ssh.client)
        }
    }

    private var remoteParent: String? {
        let path = model.currentRemotePath
        guard path != settings.hermesDirectory, path != settings.tipsDirectory else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }
}

private struct RemoteRow: View {
    let item: RemoteItem
    let open: () -> Void
    let download: (Bool) -> Void
    let preview: () -> Void

    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder" : "doc")
            VStack(alignment: .leading) {
                Text(item.name)
                HStack {
                    if let size = item.size, !item.isDirectory { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
                    if let date = item.modifiedAt { Text(date, style: .date) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDirectory { Button(action: open) { Image(systemName: "chevron.right") } }
            Menu {
                if !item.isDirectory { Button("Preview") { preview() } }
                Button("Download") { download(false) }
                Button("Download & Export") { download(true) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private struct LocalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        List {
            NavigationLink { LocalDirectoryView(directoryName: settings.exportDirectory) } label: {
                Label(settings.exportDirectory, systemImage: "tray.full")
            }
            NavigationLink { LocalDirectoryView(directoryName: settings.tipsLocalDirectory) } label: {
                Label(settings.tipsLocalDirectory, systemImage: "folder")
            }
        }
    }
}

private struct LocalDirectoryView: View {
    let directoryName: String
    @State private var items: [LocalItem] = []
    @State private var previewURL: URL?
    @State private var exportURLs: [URL] = []
    @State private var renameItem: LocalItem?
    @State private var renameText = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(items) { item in
                HStack {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                    VStack(alignment: .leading) {
                        Text(item.name)
                        if let size = item.size, !item.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if item.isDirectory {
                        NavigationLink("") { LocalURLDirectoryView(url: item.url) }.labelsHidden()
                    } else {
                        Button { previewURL = item.url } label: { Image(systemName: "eye") }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { remove(item) } label: { Label("Delete", systemImage: "trash") }
                    Button { renameItem = item; renameText = item.name } label: { Label("Rename", systemImage: "pencil") }
                }
                .contextMenu {
                    Button("Preview") { previewURL = item.url }
                    Button("Export") { exportURLs = [item.url] }
                    ShareLink(item: item.url)
                }
            }
        }
        .navigationTitle(directoryName)
        .toolbar { Button { exportRoot() } label: { Label("Export", systemImage: "square.and.arrow.up") } }
        .onAppear { reload() }
        .sheet(item: Binding(get: { previewURL.map(PreviewURL.init) }, set: { previewURL = $0?.url })) { QuickLookPreview(url: $0.url) }
        .sheet(isPresented: Binding(get: { !exportURLs.isEmpty }, set: { if !$0 { exportURLs = [] } })) {
            DocumentExporter(urls: exportURLs) { exportURLs = [] }
        }
        .alert("Rename", isPresented: Binding(get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameItem = nil }
            Button("Rename") { rename() }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func root() throws -> URL { try LocalFileStore.shared.directory(named: directoryName) }
    private func reload() { do { items = try LocalFileStore.shared.items(at: root()) } catch { errorMessage = error.localizedDescription } }
    private func remove(_ item: LocalItem) { do { try LocalFileStore.shared.delete(item.url); reload() } catch { errorMessage = error.localizedDescription } }
    private func rename() { guard let item = renameItem else { return }; do { _ = try LocalFileStore.shared.rename(item.url, to: renameText); renameItem = nil; reload() } catch { errorMessage = error.localizedDescription } }
    private func exportRoot() { do { exportURLs = [try root()] } catch { errorMessage = error.localizedDescription } }
}

private struct LocalURLDirectoryView: View {
    let url: URL
    @State private var items: [LocalItem] = []
    @State private var previewURL: URL?
    var body: some View {
        List(items) { item in
            if item.isDirectory {
                NavigationLink { LocalURLDirectoryView(url: item.url) } label: { Label(item.name, systemImage: "folder") }
            } else {
                Button { previewURL = item.url } label: { Label(item.name, systemImage: "doc") }
            }
        }
        .navigationTitle(url.lastPathComponent)
        .onAppear { items = (try? LocalFileStore.shared.items(at: url)) ?? [] }
        .sheet(item: Binding(get: { previewURL.map(PreviewURL.init) }, set: { previewURL = $0?.url })) { QuickLookPreview(url: $0.url) }
    }
}

private struct PreviewURL: Identifiable {
    let url: URL
    var id: URL { url }
}
