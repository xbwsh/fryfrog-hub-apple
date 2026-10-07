# Implement 完成报告：灵动岛 Live Activity（attempt 1）

## 实现（按设计方案 §3-§5）

- **Attributes**（`FryfrogHub/Models/MusicLiveActivityAttributes.swift`）：`MusicLiveActivityAttributes: ActivityAttributes`，`songId: Int64` 去重键 + `ContentState(title/artist/album/artworkURL/duration/position/isPlaying/updatedAt)`；该文件以源码级共享同时编入主 App 与扩展（扩展不能依赖宿主 App）。
- **Service**（`FryfrogHub/Services/MusicLiveActivityService.swift`）：`@MainActor` 单例；`isEnabled`（ActivityAuthorizationInfo.areActivitiesEnabled + #available(iOS 16.1,*) 守卫）、`startOrUpdate(song:position:isPlaying:)`（无则 request、同曲 update、换曲 end+request——attributes 不可变）、`updatePosition(force:)` 1s 节流、`pause()`/`updatePlayback(isPlaying:)` 立即推送、`end()` `.immediate`；request 前清理 songId 不符的残留实例（设计 §8）。快照 `lastState` 支撑局部翻转重发。
- **Widget Extension**（`FryfogHubLiveActivity/`）：Bundle 入口 + `MusicLiveActivityWidget`（ActivityConfiguration）；锁屏视图（封面56pt/标题歌手专辑/进度条/走秒文本/三键控制44pt 击区）；灵动岛 Compact(封面+状态图标)/Minimal(音符)/Expanded(封面+信息+进度+三键)；`.activityBackgroundTint(.black.opacity(0.85))`。
- **project.yml**：主 App 追加 `NSSupportsLiveActivities: true` 与 `CFBundleURLTypes(fryfrog scheme)`（deep link 必需）；新 target `FryfogHubLiveActivity` type app-extension、bundleId `com.fryfrog.hub.liveactivity`、DEVELOPMENT_TEAM 77FLQLNAN3、info 含 `NSExtensionPointIdentifier: com.apple.widgetkit-extension`；主 App dependencies 嵌入扩展；xcodegen 重生成 pbxproj 与两份 Info.plist。
- **埋点**（`MusicAudioPlayer.swift`，12 处）：play/toggle 恢复/playCurrent/pauseWithFade/pauseImmediately(视频抢占)/seek(force)/timeObserver(节流1s)/handleTrackEnded×3 分支/playNext×2 分支/playPrevious×3 分支/stop(end)/interruption 恢复同步；MPNowPlayingInfoCenter 链路未动。
- **交互**：按指示首版 widgetURL deep link `fryfrog://music/toggle|next|previous`，App.onOpenURL → `MusicAudioPlayer.handleLiveActivityURL` 派发；AppIntent 二期 TODO 已注释在 MusicLiveActivityLink。

## 已知限制 / 待复核

1. **灵动岛内不支持 Link**（系统限制）：紧凑/最小形态整岛点击经 widgetURL 回跳 App；锁屏与灵动岛展开区的三键为 Link 独立派发。若要求不唤起 App 的岛内直接控制，需二期 AppIntent + App Group（免费团队签名受限），已留 TODO。
2. **封面加载**：扩展侧 AsyncImage 直连不带鉴权头，若服务器封面需鉴权将回退占位音符；真机验证项。
3. **单测顺延**：设计方案 §7 的 Service 单测未补——`FryfrogHubTests/**` 不在本 attempt writablePaths（仅 FryfrogHub/**、FryfrogHubLiveActivity/**、project.yml、xcodeproj/**），需 Leader 授权扩写路径后补测。
4. **真机验收**（模拟器无法覆盖）：iPhone 14 Pro+ 灵动岛出现/展开/收起、控制回跳生效、锁屏 LA 同步；对应设计方案 §9.5。

## 工作树说明

工作树中存在**他人未提交的 T5-1 改动**（MpvMetalView.swift / MpvMetalViewContainer.swift / MpvPlayer.swift，后台渲染方向，含对上轮 F-002/F-003 的处置），本任务未触碰；本次构建测试连带编译了这些改动并全部通过。
