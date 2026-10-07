# Rework 决策 — 移除灵动岛

**决策**: required=true

**背景**: 用户在 workflow 运行中变更需求：从“接入灵动岛”改为“移除灵动岛，音乐后台播放使用系统组件就行”。

**已执行移除** (Leader 直接实施，impl 已 APPROVED 但需逆向):
- 删除 `FryfrogHubLiveActivity/` 整个扩展（含 LockScreen/DynamicIsland Views、Widget/Bundles）
- 删除 `FryfrogHub/Models/MusicLiveActivityAttributes.swift` 与 `FryfrogHub/Services/MusicLiveActivityService.swift`
- 回退 `MusicAudioPlayer.swift:1` 至 HEAD（移除 12 处 MusicLiveActivityService 调用与 handleLiveActivityURL，保留 AVPlayer + AVAudioSession playback + MPNowPlayingInfoCenter:388 + MPRemoteCommandCenter:77）
- 回退 `FryfrogHubApp.swift:18` 移除 onOpenURL deep link
- 回退 `project.yml:55` 移除 FryfrogHubLiveActivity target、NSSupportsLiveActivities、CFBundleURLTypes(fryfrog)
- xcodegen regenerate → project.pbxproj 不再含 LiveActivity，xcodebuild build BUILD SUCCEEDED + stale .o 清理（MusicLiveActivityAttributes.o/Service.o）

**系统后台播放保留**:
- UIBackgroundModes audio 仍在 Info.plist
- AVAudioSession.setCategory(.playback, mixWithOthers) 延迟激活
- configureNowPlaying 与 remote commands 完整

**下一步**: verify 阶段由 reviewer 复核系统组件链路无损。
