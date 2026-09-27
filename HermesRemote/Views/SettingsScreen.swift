import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ssh: SSHService
    @State private var importingKey = false
    @State private var hasPrivateKey = false
    @State private var password = ""
    @State private var passphrase = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("SSH") {
                    TextField("Host (VPN/Tailscale IP or name)", text: $settings.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("settings.host")
                    TextField("Port", value: $settings.port, format: .number)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("settings.port")
                    TextField("Username", text: $settings.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("settings.username")

                    Picker("認証方式", selection: $settings.authenticationKind) {
                        ForEach(SSHAuthenticationKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settings.authenticationKind == .password {
                        SecureField("SSHパスワード", text: $password)
                            .textContentType(.password)
                            .accessibilityIdentifier("settings.password")
                        Button("パスワードをKeychainへ保存") { savePassword() }
                    } else {
                        HStack {
                            Label(hasPrivateKey ? "秘密鍵: 保存済み" : "秘密鍵: 未設定",
                                  systemImage: hasPrivateKey ? "key.fill" : "key")
                            Spacer()
                            Button("読込") { importingKey = true }
                        }
                        SecureField("秘密鍵のパスフレーズ（任意）", text: $passphrase)
                        Button("パスフレーズをKeychainへ保存") { savePassphrase() }
                    }
                    Button("登録済みホスト鍵を削除", role: .destructive) {
                        do { try ssh.forgetHostKey(settings: settings); message = "ホスト鍵を削除しました。" }
                        catch { message = error.localizedDescription }
                    }
                }
                Section("Hermes") {
                    TextField("Startup Command", text: $settings.startupCommand, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("tmux Session Name", text: $settings.tmuxSession)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Remote Files") {
                    TextField("Hermes Share Directory", text: $settings.hermesDirectory)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Tips Directory", text: $settings.tipsDirectory)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Local") {
                    TextField("Export Directory Name", text: $settings.exportDirectory)
                    TextField("Tips Directory Name", text: $settings.tipsLocalDirectory)
                    Text("DocumentsはiOSの「ファイル」アプリからも参照できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Network") {
                    Text("このアプリはVPNを構成しません。外出先ではTailscale等でDGXへ安全に到達できる状態にしてください。SSHポートの直接公開は推奨しません。")
                        .font(.footnote)
                }
            }
            // 設定中の軽いスクロールでキーボードが消えないようにする。
            // 閉じる操作はキーボード上の「完了」に一本化する。
            .scrollDismissesKeyboard(.never)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { dismissKeyboard() }
                }
            }
            .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data, .plainText]) { result in
                do {
                    let url = try result.get()
                    guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    guard String(data: data, encoding: .utf8)?.contains("PRIVATE KEY") == true else {
                        throw HermesRemoteError.unsupportedPrivateKey
                    }
                    try KeychainStore.shared.set(data, account: KeychainStore.Account.privateKey)
                    hasPrivateKey = true
                    message = "秘密鍵をKeychainへ保存しました。"
                } catch { message = error.localizedDescription }
            }
            .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onAppear { refreshCredentialStatus() }
            .onDisappear { dismissKeyboard() }
            .onChange(of: settings.authenticationKind) { _, _ in dismissKeyboard() }
        }
    }

    private func refreshCredentialStatus() {
        hasPrivateKey = (try? KeychainStore.shared.data(account: KeychainStore.Account.privateKey)) != nil
        password = (try? KeychainStore.shared.string(account: KeychainStore.Account.password)) ?? ""
        passphrase = (try? KeychainStore.shared.string(account: KeychainStore.Account.keyPassphrase)) ?? ""
    }

    private func savePassword() {
        do {
            if password.isEmpty { try KeychainStore.shared.delete(account: KeychainStore.Account.password) }
            else { try KeychainStore.shared.set(password, account: KeychainStore.Account.password) }
            dismissKeyboard()
            message = password.isEmpty ? "保存済みパスワードを削除しました。" : "パスワードをKeychainへ保存しました。"
        } catch { message = error.localizedDescription }
    }

    private func savePassphrase() {
        do {
            if passphrase.isEmpty { try KeychainStore.shared.delete(account: KeychainStore.Account.keyPassphrase) }
            else { try KeychainStore.shared.set(passphrase, account: KeychainStore.Account.keyPassphrase) }
            message = "Keychainへ保存しました。"
        } catch { message = error.localizedDescription }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
