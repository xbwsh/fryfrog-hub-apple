# 变更清单：Phase 0-2 + T3-4/T3-5 重构交付

> 作者：Executor-A/B/C 合并交付（ox-alpha 会话）
> 时间：2026-08-22
> 提交范围：`9e8c79b..c1d4449`（共 9 个提交，含初始化）
> 验证证据：`xcodegen generate` 无 error；`xcodebuild -configuration Release -destination 'generic/platform=iOS' build` → **BUILD SUCCEEDED，0 warning / 0 error**；`git status` 干净

## 提交索引

| 提交 | 任务 | 说明 |
|---|---|---|
| `9e8c79b` | T0-1 | git 初始化 + .gitignore |
| `510ccbd` | T0-2 | 清理 build/；工程警告修复，Release 构建零告警 |
| `fe2140a` | T1-1/2/3 | 并发与崩溃隐患修复 |
| `271e375` | T2-1 | MusicView 拆分 13 文件 |
| `75ba045` | T2-2 | MpvVideoPlayerView 辅助类型外迁 |
| `60d55f8` | T2-3 | ProfileView 拆分 5 文件 |
| `5589245` | T2-4 | SeriesDetailView 抽出枚举 |
| `c1d4449` | T3-4/T3-5 | setStar 收敛 + host 校验去重 |

## 文件清单

### 新增
- `.gitignore`
- `FryfrogHub/Support/AsyncSemaphore.swift`
- `FryfrogHub/Views/Music/`：MusicSongRow / MusicAlbumCard / MusicArtistCard / MusicAlbumView / MusicArtistView / MusicPlaylistRow / MusicPlaylistView / PlaylistSongRow / CreatePlaylistSheet / AddToPlaylistSheet / MusicMiniPlayer / MusicNowPlayingView / LyricsLine（13 个，纯搬运）
- `FryfrogHub/Views/Profile/`：SupportDeveloperView / ChangePasswordView / UsersManagementView / UserEditView / LibraryAccessView（5 个，纯搬运）
- `FryfrogHub/Views/Player/`：FlatSlider / HiddenVolumeView / MpvMetalViewContainer / PlayerSupportTypes（4 个，纯搬运）
- `FryfrogHub/Views/Home/EpisodeDisplayMode.swift`（纯搬运）
- `FryfrogHub/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- `FryfrogHub/Resources/Assets.xcassets/AppIcon.appiconset/Icon-76@2x.png`、`Icon-83.5@2x.png`

### 修改
- `project.yml`：ALWAYS_SEARCH_USER_PATHS=NO、Embed 脚本 basedOnDependencyAnalysis=false、UIRequiresFullScreen=true
- `FryfrogHub/Views/Shared/ServerImageView.swift`：下载限流改 AsyncSemaphore.withPermit（T1-1 核心）
- `FryfrogHub/Views/Player/MpvMetalView.swift`：init 改可失败，try!/fatalError 清零（T1-2 核心）
- `FryfrogHub/Views/Player/MpvVideoPlayerView.swift`：MpvMetalViewContainer 回退占位 + onFailure；主视图保持整体
- `FryfrogHub/Views/Player/MpvPlayer.swift`：RunningFlag 锁保护标志、nonisolated handleEvent、PropertyValue 事件线程内解码（T1-3 核心）
- `FryfrogHub/Networking/APIConfig.swift`：setActiveMode/updateIsProbing 统一 MainActor.run；新增 HostValidator
- `FryfrogHub/Networking/MusicService.swift`：setStar 本地同步段重写为 updating(...) 调用（T3-4 核心）
- `FryfrogHub/Models/MusicModels.swift`：MusicSong/MusicAlbum/MusicArtist/MusicLibraryGroup 新增 updating(...) 扩展
- `FryfrogHub/Views/Login/LoginViewModel.swift`：isValid 复用 HostValidator（T3-5）
- `FryfrogHub/Views/Home/CalendarView.swift`、`Services/MusicAudioPlayer.swift`、`Views/Player/SystemVideoPlayerView.swift`、`Views/Music/MusicView.swift`：存量告警小修（var→let、`_ = try?` 等）

### 生成物（随 xcodegen 再生成）
- `FryfrogHub.xcodeproj/project.pbxproj`

## 建议审查重点（按风险排序）

1. **AsyncSemaphore 许可语义**：`Support/AsyncSemaphore.swift` — wait 排队 FIFO、signal 移交队首、withPermit 异常路径归还；不感知取消的取舍已注释
2. **MpvPlayer.swift:412-470 事件循环**：nonisolated handleEvent 是否确实无隔离状态访问；PropertyValue.decode 与旧 format-per-name 判定行为等价性；RunningFlag 锁窗口
3. **Metal 失败传导链**：`MpvMetalView.init?` 四个失败点 → `MpvMetalViewContainer.makeUIView` 占位回退 → `handleRenderFailure` 复用 errorMessage UI；确认失败后不重复上报
4. **setStar 行为等价**：三分支 + selectedAlbum/selectedArtist 更新与原逐字段构造逐一对照
5. **拆分纯度抽查**：任选 2-3 个新文件与 `9e8c79b^`（即初始提交）中 MusicView.swift 对应行段 diff 比对，应仅差 `private struct`→`struct` 与 import 头

## 已知偏差（主动申报）

- `MusicNowPlayingView.swift`(708行)/`MpvVideoPlayerView.swift`(1280行)/`SeriesDetailView.swift`(851行) 未达 <300 行验收线：单 struct 共享 @State 强耦合，拆分必然改状态流，按任务单风险注记保持整体
- T3-1（协议抽象）/T3-2（单测 target）/T3-3（try? 日志）未实施，留待下一轮（依赖关系：T3-2 依赖 T3-1）
