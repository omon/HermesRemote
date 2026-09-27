import SwiftUI

struct TerminalScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ssh: SSHService

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(ssh.state.label).font(.caption).lineLimit(1)
                    if ssh.state == .connected {
                        Text(ssh.isInputReady ? "入力可" : "入力準備中")
                            .font(.caption2)
                            .foregroundStyle(ssh.isInputReady ? Color.secondary : Color.orange)
                    }
                    Spacer()
                    if ssh.state == .connected {
                        Button {
                            ssh.focusTerminal()
                        } label: {
                            Image(systemName: "keyboard")
                        }
                        .accessibilityLabel("キーボードを表示")
                        .disabled(!ssh.isInputReady)
                        Button("切断") { ssh.disconnect() }
                    } else {
                        Button("接続") { ssh.connect(settings: settings) }
                            .disabled(ssh.state == .connecting)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)

                TerminalContainer(service: ssh)
                    .background(Color.black)

                AccessoryKeys(send: { ssh.send($0) }, dismissKeyboard: {
                    ssh.dismissTerminalKeyboard()
                })
                    .background(.bar)
            }
            .navigationTitle(ssh.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: ssh.state) { _, newState in
                guard newState == .connected else { return }
                Task { @MainActor in
                    await Task.yield()
                    ssh.focusTerminal()
                }
            }
            .alert("SSHホスト鍵を確認", isPresented: Binding(
                get: { ssh.pendingFingerprint != nil }, set: { if !$0 { ssh.disconnect() } }
            )) {
                Button("拒否", role: .cancel) { ssh.disconnect() }
                Button("この鍵を登録して接続") { ssh.approvePendingHostKey() }
            } message: {
                Text("DGX側で次のSHA-256フィンガープリントと一致することを確認してください。\n\n\(ssh.pendingFingerprint ?? "")")
            }
        }
    }

    private var statusColor: Color {
        switch ssh.state {
        case .connected: .green
        case .connecting, .awaitingHostApproval: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}

private struct AccessoryKeys: View {
    let send: ([UInt8]) -> Void
    let dismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    key("ESC", [0x1b])
                    Menu("CTRL") {
                        Button("Ctrl-C") { send([0x03]) }
                        Button("Ctrl-D") { send([0x04]) }
                        Button("Ctrl-L") { send([0x0c]) }
                        Button("Ctrl-Z") { send([0x1a]) }
                    }.buttonStyle(.bordered)
                    key("TAB", [0x09])
                    key("ENTER", [0x0d])
                    key("↑", Array("\u{1b}[A".utf8)); key("↓", Array("\u{1b}[B".utf8))
                    key("←", Array("\u{1b}[D".utf8)); key("→", Array("\u{1b}[C".utf8))
                    key("PGUP", Array("\u{1b}[5~".utf8)); key("PGDN", Array("\u{1b}[6~".utf8))
                }
                .padding(8)
            }

            Divider().frame(height: 32)
            Button {
                dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("キーボードを閉じる")
            .padding(.horizontal, 8)
        }
    }

    private func key(_ title: String, _ bytes: [UInt8]) -> some View {
        Button(title) { send(bytes) }.buttonStyle(.bordered)
    }
}
