# 実機受け入れチェックリスト

## 接続とセキュリティ

- [ ] VPN/Tailscaleありで接続でき、なしでは理解できるエラーになる
- [ ] 初回接続でホスト鍵フィンガープリントが表示される
- [ ] DGXの `ssh-keygen -lf ... -E sha256` と一致した鍵だけを承認する
- [ ] DGXと異なる登録済み鍵では接続が拒否される
- [ ] Ed25519秘密鍵（平文／暗号化）で認証できる
- [ ] Keychainに保存したSSHパスワードで認証できる
- [ ] アプリログやUserDefaultsにSSHパスワード・秘密鍵・パスフレーズがない

## Terminal / Hermes

- [ ] `uname -a` の出力を確認できる
- [ ] ANSI色、256色、罫線、絵文字、日本語が崩れない
- [ ] 日本語入力、選択、コピー、ペースト、スクロールが動く
- [ ] Portrait / LandscapeでPTY resizeされる
- [ ] 補助キー（ESC / CTRL / TAB / 矢印 / PGUP / PGDN）が動く
- [ ] tmuxへattachし、Hermes TUIを操作できる
- [ ] アプリ終了後もHermesが継続し、再接続で同じtmuxへ戻る

## Files / USB

- [ ] Hermes Shareの一覧、サイズ、更新日時を確認できる
- [ ] txt / md / c / cpp / h / py / json / yaml / diff / html等をDownloadできる
- [ ] DownloadしたファイルをQuick LookでPreviewできる
- [ ] Rename / Delete / Shareが動く
- [ ] USB-CメモリをDocument Pickerの保存先に選べる
- [ ] USBへExportしたファイルをWindowsで開ける
- [ ] TipsのHTML/CSS/JS/images階層が維持される
- [ ] USBへExportしたTipsの `index.html` をWindowsで開き、リンクと画像が壊れない
- [ ] Download & Exportが連続して動く
