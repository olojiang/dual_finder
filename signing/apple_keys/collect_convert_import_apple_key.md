# Apple 签名材料收集、转换与导入说明

本目录用于把 `spatial-smart-cc` 里 `pnpm build:desktop` 使用的 Apple 签名材料收集到一个独立位置，转换旧式 PKCS#12 证书，并导入到 macOS keychain。

源仓库：

```bash
/Users/hunter/Workspace/spatial-smart-cc
```

输出目录：

```bash
/Users/hunter/Workspace/apple_keys
```

## 背景

`spatial-smart-cc` 的桌面构建入口是：

```bash
pnpm build:desktop
```

它会调用：

```bash
./scripts/clean-dmg.sh && ./scripts/build-macos-dist.sh build
```

签名材料主要来自：

```bash
/Users/hunter/Workspace/spatial-smart-cc/scripts/build-macos-dist.sh
```

该脚本内嵌了 Developer ID Application 的 PKCS#12/base64 内容，证书身份是：

```text
Developer ID Application: Pine Field Inc (Y8JR7FG9SR)
```

这个内嵌 PKCS#12 使用旧式 `RC2-40-CBC` 加密。当前系统的 `security import` 直接导入会失败：

```text
SecKeychainItemImport: Import/Export format unsupported.
```

解决方式是先用 OpenSSL legacy 模式解出证书和私钥，再重新导出现代 PKCS#12，然后导入 keychain。

## 脚本

### 1. 收集和转换

脚本路径：

```bash
/Users/hunter/Workspace/apple_keys/collect_and_convert.sh
```

运行：

```bash
cd /Users/hunter/Workspace/apple_keys
./collect_and_convert.sh
```

默认从以下仓库收集：

```bash
/Users/hunter/Workspace/spatial-smart-cc
```

如果要换源仓库：

```bash
SOURCE_REPO=/path/to/spatial-smart-cc ./collect_and_convert.sh
```

生成文件：

```text
developer_id_application_pine_field_legacy.p12   # 原始旧式 PKCS#12
developer_id_application_pine_field_modern.p12   # 转换后的现代 PKCS#12，用于 security import
developer_id_application_pine_field_cert.pem     # 证书 PEM，仅用于检查证书信息
AuthKey_B22483VZKL.p8                            # Apple notary API key
tauri_updater.key                                # Tauri updater 私钥
tauri_updater.key.pub                            # Tauri updater 公钥
apple_key_metadata.env                           # 非密码路径和身份信息
apple_key_secrets.env                            # 密码信息，权限 600
```

脚本会打印证书 subject、SHA1 fingerprint 和 serial，但不会打印私钥内容。

### 2. 导入 keychain

脚本路径：

```bash
/Users/hunter/Workspace/apple_keys/import_into_keychain.sh
```

运行：

```bash
cd /Users/hunter/Workspace/apple_keys
./import_into_keychain.sh
```

默认导入到：

```bash
~/Library/Keychains/apple-build-signing.keychain-db
```

如果要指定 keychain 名：

```bash
KEYCHAIN_NAME=spatial-smart-signing.keychain-db ./import_into_keychain.sh
```

如果 keychain 不存在，脚本会创建；如果已经存在，脚本会复用。脚本会先检查目标签名身份是否已经存在，存在时跳过重复导入，但仍会刷新 key partition list，保证 `codesign` 可用。

导入后脚本会执行：

```bash
security find-identity -v -p codesigning ~/Library/Keychains/apple-build-signing.keychain-db
```

并验证其中包含：

```text
Developer ID Application: Pine Field Inc (Y8JR7FG9SR)
```

## 验证命令

检查收集产物：

```bash
ls -la /Users/hunter/Workspace/apple_keys
openssl x509 -in /Users/hunter/Workspace/apple_keys/developer_id_application_pine_field_cert.pem -noout -subject -fingerprint -sha1 -serial
```

检查 keychain 签名身份：

```bash
security find-identity -v -p codesigning ~/Library/Keychains/apple-build-signing.keychain-db
```

预期能看到：

```text
Developer ID Application: Pine Field Inc (Y8JR7FG9SR)
```

做一次实际 `codesign` 测试：

```bash
tmpdir="$(mktemp -d /tmp/apple-sign-test.XXXXXX)"
cat > "$tmpdir/main.c" <<'EOF'
int main(void) { return 0; }
EOF
cc "$tmpdir/main.c" -o "$tmpdir/sign-test"
codesign --force --timestamp=none --options runtime \
  --sign "Developer ID Application: Pine Field Inc (Y8JR7FG9SR)" \
  --keychain "$HOME/Library/Keychains/apple-build-signing.keychain-db" \
  "$tmpdir/sign-test"
codesign -dv "$tmpdir/sign-test" 2>&1 | rg 'Authority|TeamIdentifier|Runtime|Identifier'
rm -rf "$tmpdir"
```

预期至少能看到：

```text
TeamIdentifier=Y8JR7FG9SR
Runtime Version=...
```

## 本机已验证结果

已经在本机完成以下验证：

```bash
cd /Users/hunter/Workspace/apple_keys
./collect_and_convert.sh
./import_into_keychain.sh
bash -n collect_and_convert.sh
bash -n import_into_keychain.sh
security find-identity -v -p codesigning ~/Library/Keychains/apple-build-signing.keychain-db
```

导入后的身份：

```text
Developer ID Application: Pine Field Inc (Y8JR7FG9SR)
```

实际签名临时 Mach-O 后确认：

```text
TeamIdentifier=Y8JR7FG9SR
Runtime Version=15.2.0
```

## 当前脚本可靠性结论

当前流程对本机 `spatial-smart-cc` 签名材料是可用的：

- `collect_and_convert.sh` 会检查源构建脚本、Apple notary API key 和 Tauri updater key 是否存在。
- 旧式 PKCS#12 会通过 OpenSSL legacy 模式转换成可由 macOS `security import` 接受的现代 PKCS#12。
- 生成的 `.env` 文件使用 Bash 转义格式，路径或值里出现空格等特殊字符时仍可被 `source` 读取。
- `import_into_keychain.sh` 会安全保留现有 user keychain 列表，并避免重复导入同一签名身份。
- 敏感产物权限保持为 `600`，脚本权限为 `700`。

## 安全注意

`apple_key_secrets.env`、`*.p12`、`AuthKey_*.p8`、`tauri_updater.key` 都是敏感文件，只应保存在本机安全目录中，不要提交到 git，不要通过聊天或日志外发。

本目录脚本默认把敏感文件权限设为 `600`。
