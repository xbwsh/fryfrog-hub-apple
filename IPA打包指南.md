# FryfrogHub IPA 打包指南

本指南记录 FryfrogHub（iOS，SwiftUI，XcodeGen 工程）在**免费 Apple ID 开发签名**下的完整 IPA 打包流程，以及常见问题与签名限制。

> 适用于本机环境：macOS + Xcode 17，免费团队 `77FLQLNAN3`，唯一签名身份 `Apple Development: ajiangqaq@163.com (CUB7NCT6C8)`，仅一台已注册设备（iPhone 17 Pro Max）。

---

## 1. 前置检查

### 1.1 验证签名身份

```bash
security find-identity -v -p codesigning
```

应输出至少一个 `Apple Development:` 身份。若为空，需要在 Xcode → Settings → Accounts 登录 Apple ID。

### 1.2 确认工程结构

项目由 XcodeGen 管理，`FryfrogHub.xcodeproj` 由 `project.yml` 生成：

```bash
ls project.yml        # 源定义
ls FryfrogHub.xcodeproj  # 生成的工程（勿手改）
```

若改了 `project.yml`，需重新生成工程后再打包：

```bash
xcodegen generate
```

### 1.3 编译自检（先跑模拟器，最快暴露代码问题）

```bash
xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -destination 'generic/platform=iOS Simulator' build
```

输出含 `** BUILD SUCCEEDED **` 才继续。

---

## 2. 首次打包前：注册设备并生成描述文件（只需一次）

免费团队必须把真机 UDID 加入账号并生成开发描述文件，Xcode 才能对真机签名。

### 2.1 连接设备，向设备构建一次

```bash
xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -configuration Release \
  -destination 'platform=iOS,id=<设备UDID>' \
  -allowProvisioningUpdates build
```

期间 Xcode 会自动：
- 注册设备 UDID 到开发者账号；
- 自动生成 `iOS Team Provisioning Profile: com.fryfrog.hub`。

> `-allowProvisioningUpdates` 允许 Xcode 自动管理描述文件。这一步成功后，后续 archive 即可复用该 profile。
>
> 设备 UDID 可通过 `xcrun devicectl list devices` 查看。

### 2.2 验证描述文件（可选）

```bash
security cms -D -i <app路径>/embedded.mobileprovision -o /tmp/pp.plist
/usr/libexec/PlistBuddy -c "Print :Name" -c "Print :ExpirationDate" -c "Print :ProvisionedDevices" /tmp/pp.plist
```

免费开发 profile 有效期约 7 天，**过期后需重新执行第 2 步**。

---

## 3. 打包 IPA（正式流程）

### 3.1 归档（Archive，Release 配置）

```bash
rm -rf build/release/ipa build/release/FryfrogHub.ipa
xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -configuration Release \
  -archivePath build/release/FryfrogHub.xcarchive \
  -allowProvisioningUpdates archive
```

成功标志：`** ARCHIVE SUCCEEDED **`。产物在 `build/release/FryfrogHub.xcarchive`。

### 3.2 手工打包成 IPA（本机首选路径）

> 说明：`exportArchive`（development）在本机会报 `No signing certificate "iOS Development" found`——证书名匹配问题，属环境限制。绕过办法是直接从归档拷贝 `.app` 手工打包，签名校验通过、可正常安装。

```bash
# 1. 建 Payload 目录并拷贝 app
mkdir -p build/release/ipa/Payload
cp -R build/release/FryfrogHub.xcarchive/Products/Applications/FryfrogHub.app build/release/ipa/Payload/

# 2. 压缩为 ipa（zip 根必须是 Payload/ 目录）
cd build/release/ipa && zip -qry - . > ../FryfrogHub.ipa && cd ../..

# 3. 签名与产物校验
codesign --verify --deep --strict build/release/ipa/Payload/FryfrogHub.app && echo "codesign VERIFY OK"
ls -lh build/release/FryfrogHub.ipa
```

### 3.3 产物

- **`build/release/FryfrogHub.ipa`** — 最终交付物（约 7.8MB）
- `build/release/FryfrogHub.xcarchive` — 归档包（可保留，用于后续导出/上架）
- `build/release/ipa/` — Payload 中间产物（可随时清理）

---

## 4. 安装到设备

方式一：**Xcode → Devices and Simulators → 拖入 ipa**（或选 App → 拖到设备）。

方式二：命令行安装：

```bash
xcrun devicectl device install app --device <UDID> build/release/FryfrogHub.ipa
```

安装后首页图标正常即成功。若安装失败，检查描述文件是否过期（第 2 步重跑一次）。

---

## 5. 常见问题排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `No signing certificate "iOS Development" found` | 证书名与工程期望不匹配（本机仅 1 个身份） | 走 3.2 手工打包，忽略 exportArchive |
| 安装报“无法安装 App / 描述文件无效” | 开发描述文件过期（~7 天） | 重新执行第 2 步真机构建 |
| `No profiles for 'com.fryfrog.hub' were found` | 免费账号未注册设备 | 连接设备执行第 2 步 |
| 模拟器编译报错 | 代码问题 | 先修代码，重复 1.3 自检 |
| UDID 变了 / 换新设备 | 设备不在描述文件中 | 新设备插上重跑第 2 步 |

---

## 6. 签名限制与发布说明

- 当前为 **Development 签名**：仅能安装到已注册的这台 iPhone，有效期短（profile ~7 天），到期重签。
- 免费 Apple ID 无法打 **Ad Hoc / TestFlight / App Store** 包——这些需要 Apple Developer Program（¥688/年）+ Distribution 证书。
- 若后续要正式分发，需要：付费账号 → 创建 Distribution 证书 → 注册全部目标设备（Ad Hoc）或上架 TestFlight/App Store，流程会改为 `exportArchive -exportMethod ad-hoc`（或 app-store）。
- 本指南所有路径均为仓库内 `build/release/` 相对路径，可直接在项目根目录执行。

---

*最后更新：2026-08-14*
---

## 7. GitHub Actions 自动打包（CI）

仓库内置工作流 [`.github/workflows/ipa.yml`](.github/workflows/ipa.yml)，每次推送到 `main`（或打 `v*` tag、手动触发）都会：

1. **模拟器编译自检**（无需 Secrets，任何提交都校验可编译）
2. **签名打包 IPA**（需配置 Secrets，产物以 Artifact 形式保留 14 天）

### 7.1 配置三个仓库 Secrets

在 [GitHub → Settings → Secrets and variables → Actions](https://github.com/xbwsh/fryfrog-hub-apple/settings/secrets/actions) 添加：

| Secret | 内容 |
|---|---|
| `IOS_SIGNING_CERT_BASE64` | 开发证书 `.p12` 的 Base64 |
| `IOS_SIGNING_CERT_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `com.fryfrog.hub` 开发描述文件 `.mobileprovision` 的 Base64 |

导出证书（本机）：

```bash
security find-identity -v -p codesigning          # 记下身份 SHA1，如 65F6...
security export -k login.keychain -t certs -f pkcs12 \
  -P "你的p12密码" -o /tmp/fryfrog.p12 <SHA1>
base64 -i /tmp/fryfrog.p12 | tr -d '\n' | pbcopy   # 粘贴到 Secret
```

提取描述文件（需先按第 2 步真机构建一次生成 profile）：

```bash
ls ~/Library/MobileDevice/Provisioning\ Profiles/  # 取最新的 .mobileprovision
base64 -i <该文件> | tr -d '\n' | pbcopy           # 粘贴到 Secret
```

命令行设置（等效）：

```bash
gh secret set IOS_SIGNING_CERT_BASE64 --repo xbwsh/fryfrog-hub-apple
gh secret set IOS_SIGNING_CERT_PASSWORD --repo xbwsh/fryfrog-hub-apple
gh secret set IOS_PROVISIONING_PROFILE_BASE64 --repo xbwsh/fryfrog-hub-apple
```

### 7.2 注意事项

- 免费开发描述文件约 **7 天过期**，过期后 CI 签名步骤会失败：重新插手机跑一次第 2 步，把新 profile 重新上传 `IOS_PROVISIONING_PROFILE_BASE64` 即可。
- 证书（p12）有效期一年，到期后重新导出上传。
- 未配置 Secrets 时 CI 只跑编译自检，IPA 任务自动跳过。
- 产物下载：Actions 运行页 → 底部 Artifacts → `FryfrogHub-IPA`。
