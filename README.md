# FryfrogHub (iOS)

个人 NAS 媒体库的 iOS 客户端（SwiftUI，iOS 17+）。对接服务端 `fryfrog-hub-api`，支持局域网/公网自动切换、mpv 内核硬解播放、TMDB 元数据刮削、多用户与媒体库授权等。

## 功能

- **内外网切换连接**：局域网优先，自动探测回退公网，登录/影视/我的页全程可切换
- **媒体库管理（管理员）**：增删改、启停、扫描、排序、目录浏览、扫描进度轮询
- **播放**：mpv 内核（libmpv + Metal 渲染，任意格式直通、ASS 特效字幕）/ 系统播放器切换，软/硬解可选
- **元数据**：TMDB 绑定/刷新、封面/横屏/Logo 管理、季海报、观看进度同步
- **多用户**：用户名密码登录、token 持久化（Keychain）、用户管理（ADMIN）、媒体库授权分配、普通用户自动隐藏管理入口
- **用户偏好云同步**：主题/播放/隐私/字幕偏好登录拉取 + 变更防抖上传（按账号隔离）
- **隐私模式**：隐藏/模糊成人内容

## 工程结构

```
project.yml              # XcodeGen 源定义（.xcodeproj 由它生成，勿手改）
FryfrogHub.xcodeproj/    # 生成的工程
FryfrogHub/
  App/                   # 入口、Tab、RootView
  Models/                # API 数据模型
  Networking/            # APIClient / AuthService / 各 Service / ServerConnection
  Storage/               # TokenStore(Keychain) / Theme / Player / Privacy 设置
  Views/                 # Home / Library / Player / Profile / Login / Shared
  Vendor/                # 第三方框架（libmpv 等）
build/release/           # IPA 归档与产物
IPA打包指南.md            # 完整打包流程（同步见下方 README）
```

## 打包 IPA

完整流程见 [IPA打包指南.md](IPA打包指南.md)。要点速览：

### 一次性准备（仅首次 / profile 过期后）

连接 iPhone 后执行一次真机构建，让 Xcode 注册设备并自动生成开发描述文件：

```bash
xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -configuration Release -destination 'platform=iOS,id=<UDID>' \
  -allowProvisioningUpdates build
```

### 归档

```bash
rm -rf build/release/ipa build/release/FryfrogHub.ipa
xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -configuration Release -archivePath build/release/FryfrogHub.xcarchive \
  -allowProvisioningUpdates archive
```

### 手工打包 IPA（本机首选，绕过 exportArchive 证书名不匹配）

```bash
mkdir -p build/release/ipa/Payload
cp -R build/release/FryfrogHub.xcarchive/Products/Applications/FryfrogHub.app build/release/ipa/Payload/
cd build/release/ipa && zip -qry - . > ../FryfrogHub.ipa && cd ../..
codesign --verify --deep --strict build/release/ipa/Payload/FryfrogHub.app && echo "codesign VERIFY OK"
```

产物：`build/release/FryfrogHub.ipa`（约 7.8MB）。

### 安装到设备

```bash
xcrun devicectl device install app --device <UDID> build/release/FryfrogHub.ipa
```

### 注意事项

- 当前为 **Development 签名**（免费团队 `77FLQLNAN3`）：仅能装到已注册的这台 iPhone，描述文件约 **7 天** 过期，过期后重跑“一次性准备”即可。
- 需要 TestFlight / App Store / 多设备分发：需 Apple Developer Program（¥688/年）+ Distribution 证书，导出方式改为 `exportArchive -exportMethod ad-hoc|app-store`。
- 常见报错排查见 [IPA打包指南.md](IPA打包指南.md) 第 5 节。
