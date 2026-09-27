# Hermes Remote for iPhone

Hermes Remoteは、自宅のDGX Spark上にあるHermes TUIへiPhoneから安全に接続し、成果物とTips一式をiPhone経由でUSB-Cメモリへ受け渡す個人用iOSアプリです。iOS 17以上を対象にSwiftUIで実装しています。

> **Vibe Coding Project** — このアプリはJunichi OhashiとOpenAI CodexによるVibe Codingで企画・実装・デバッグされました。AIが生成・提案したコードを含みます。

## 実装済み

- パスワード認証、および公開鍵認証によるSSH接続（Ed25519 / RSA OpenSSH秘密鍵、暗号化鍵のパスフレーズ対応）
- 初回接続時のSHA-256ホスト鍵確認とKeychainへの登録、変更時の接続拒否
- PTYとSwiftTermによるxterm-256color端末、Unicode/CJK、日本語入力、スクロール、コピー＆ペースト、画面resize
- ESC、CTRL、TAB、矢印、PGUP、PGDN補助キー
- Startup Commandの実行（既定は `tmux new-session -A -s hermes`）
- SFTPによるRemote一覧、サイズ・更新日表示、単体Download、Download & Export
- Tipsディレクトリの構造を維持した再帰Download
- Documents内の `exports/` / `tips/` 一覧、Quick Look Preview、Rename、Delete、Share
- iOS Document Pickerによるファイル／フォルダExport（USB-Cメモリは保存先として「ファイル」UIから選択）
- `UIFileSharingEnabled` と `LSSupportsOpeningDocumentsInPlace` によるiOS「ファイル」アプリ連携

## 採用ライブラリ（2026-09-27調査）

| 用途 | 採用 | iOS / Swift | 公開鍵・PTY・SFTP | 端末互換性・日本語 | License / 状況 |
|---|---|---|---|---|---|
| SSH/SFTP | [Citadel 0.12.1](https://github.com/orlandos-nl/Citadel/releases/tag/0.12.1) | iOS 17、SwiftPM | Ed25519/RSA等、PTY、resize、SFTPを一つの高水準APIで提供 | 端末描画は対象外 | MIT。2026年にもリリースがあり保守継続 |
| Terminal | [SwiftTerm 1.14.0](https://github.com/migueldeicaza/SwiftTerm/releases/tag/v1.14.0) | iOS 14+、UIKit埋込 | SSH transport非同梱 | VT100/xterm、ANSI/256/TrueColor、Unicode・grapheme cluster・CJK全角修正、scroll/selection | MIT。商用SSHクライアントで利用実績、活発に保守 |
| 低水準SSH候補 | [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) | Apple純Swift / SwiftNIO | SSH構成要素とPTYはあるが、production-ready clientやSFTP UIを自前統合する必要 | 対象外 | Apache-2.0。Citadelの下位層として間接採用 |
| 代替候補 | [NMSSH](https://github.com/NMSSH/NMSSH) | Objective-C / libssh2 | SSH/SFTPあり | 対象外 | MIT。Swift Concurrencyとの統合量が増えるため不採用 |

CitadelはSSH、PTY、SFTPが同じasync/await APIにまとまり、個人用MVPのコード量を抑えられるため採用しました。SwiftTermはiOS用`TerminalView`、xterm互換性、Unicode/CJKのテスト・修正実績が要件に最も合います。暗号処理・SSH・端末エミュレーションはアプリ側で再実装していません。

依存バージョンは `project.yml` で固定しています。Citadel 0.12.1は現時点でfork版swift-nio-ssh 0.3.4を使うため、同じURL/版を明示しています。

## プロジェクトを開く

`HermesRemote.xcodeproj` は生成済みです。再生成用のXcodeGen定義も含めています。

```sh
cd HermesRemote
open HermesRemote.xcodeproj
```

構成変更後にプロジェクトを再生成する場合だけ、`brew install xcodegen && xcodegen generate` を実行します。

Xcode 16以降でPackage Dependenciesを解決し、Signing & CapabilitiesのTeamとBundle Identifierを自分の値に変更して実機へRunしてください。DGXへの疎通、秘密鍵、USB-Cメモリが必要な機能はSimulatorではなく実機で確認します。

## 初回セットアップ

1. iPhone側でTailscaleまたはVPNを有効にし、DGXのSSHへ到達できる状態にする。
2. SettingsでHost、Port、Usernameを設定する。
3. 認証方式で「パスワード」を選び、SSHパスワードをKeychainへ保存する。鍵認証を使う場合は「秘密鍵」を選び、OpenSSH形式のEd25519またはRSA秘密鍵を読み込む。
4. Startup Command、Hermes Share Directory、Tips Directoryを環境に合わせる。
5. Terminalで「接続」を押し、表示されたホスト鍵フィンガープリントをDGX上の値と照合してから登録する。

DGXでフィンガープリントを確認する例:

```sh
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

### 秘密鍵認証へ移行する場合

DGXにある既存の秘密鍵をコピーするのではなく、このiPhone専用の鍵ペアをMac等で作ることを推奨します。

```sh
ssh-keygen -t ed25519 -f hermes_iphone -C hermes-iphone
ssh-copy-id -i hermes_iphone.pub USER@DGX_HOST
```

`hermes_iphone`（拡張子なしの秘密鍵）だけをAirDropまたはiCloud DriveでiPhoneの「ファイル」へ送り、Settingsの「秘密鍵」から読み込みます。読み込み後は秘密鍵がKeychainに保存されるため、「ファイル」に置いた原本は削除できます。公開鍵の `hermes_iphone.pub` はDGXの `~/.ssh/authorized_keys` に登録し、秘密鍵をDGXへ送らないでください。

## セキュリティ設計

- SSHパスワード・秘密鍵・鍵パスフレーズ・known host公開鍵は `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` のKeychain項目として保存します。
- 初回ホスト鍵を黙って受け入れません。ユーザーが帯域外でフィンガープリントを照合し、承認した場合だけ登録します。
- 登録後にホスト鍵が変わると接続を拒否します。DGXの正当な再構築後だけSettingsから既知鍵を削除してください。
- ログに秘密鍵やパスフレーズを出しません。
- SFTPのファイル名はパストラバーサルを検査してからDocumentsへ保存します。
- VPN/Tailscaleはアプリの責務外です。SSHポートをインターネットへ直接公開しないでください。

## Phase対応状況

1. SSH接続: 実装済み
2. PTY + Terminal Emulator: 実装済み
3. tmux + Hermes: Startup Commandと再接続で実装済み（実DGX確認が必要）
4. SFTP: 実装済み
5. Local Files: 実装済み
6. USB Export: Document Pickerで実装済み（実機・実USB確認が必要）
7. Tips: 再帰DownloadとフォルダExportを実装済み
8. 使い勝手: Download & Exportと補助キーは実装。自動再接続、差分Tips Update、Face IDは今後の候補

## 現在の制約

- ECDSAのOpenSSH秘密鍵はCitadel側のOpenSSHパーサ制約があるため、MVPではEd25519またはRSAを使用します。推奨はEd25519です。
- Tips更新はMVP仕様どおり全体を上書き取得します。リモートから削除された古いローカルファイルは自動削除しません。
- フォルダExport可否は保存先プロバイダに依存します。iOS/USB側がフォルダ書き出しを拒む場合は、次段階でZIPFoundation等を追加して `tips.zip` fallbackを実装します。
- バックグラウンドへ移るとiOSがSSH socketを停止する場合があります。Hermes自体はtmuxに残り、再接続で復帰します。

## 検証

Xcodeがある環境で次を実行します。

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project HermesRemote.xcodeproj -scheme HermesRemote
xcodebuild test -project HermesRemote.xcodeproj -scheme HermesRemote \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

実機では `Documentation/AcceptanceChecklist.md` に沿って各Phaseを確認してください。
