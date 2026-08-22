# 变更清单：feat/playback-controls-fix（播放页控件唤起卡顿修复）

> 作者：Executor-A（ox-alpha 会话）
> 分支：`feat/playback-controls-fix`（基线 `refactor-phase3-pass` = 82485a5）
> 提审区间：`git log --oneline refactor-phase3-pass..HEAD`
> 验证证据：每任务独立提交；Release 构建 0 warning；`xcodebuild test`（模拟器 1DE872C2）15/15 通过

## 任务证据

### T4-1 手势仲裁重构（48658da）
- 根因：`MpvVideoPlayerView.swift:121-125` `TapGesture(count:2).exclusively(before:)` 使单击被双击判定窗口阻塞 ~300ms
- 方案（时间戳自判）：
  - `MpvVideoPlayerView.swift:52-53` 新增 `lastTapAt` 状态
  - `MpvVideoPlayerView.swift:119-130` 手势层改为单击 `TapGesture().onEnded { handlePlayAreaTap() }`
  - `MpvVideoPlayerView.swift:368-384` `handlePlayAreaTap()`：首击立即 `toggleControls()`；0.3s 窗口内第二击改判 `togglePlay()` 并重置计时（防三击误判）
- 行为保持：拖动/长按走 simultaneous 手势未动；双击暂停后控件可见（与主流播放器一致）
- 门禁：Release BUILD SUCCEEDED 0 warning；测试回归绿

### T4-2 渲染让路（810bedb，验收方案二：controlsVisible 时降帧率）
- `Views/Player/MpvMetalView.swift:96-101` `setControlsVisible(_:)`：CADisplayLink.preferredFramesPerSecond 30 ↔ 0（默认满帧）
- `Views/Player/MpvMetalViewContainer.swift` 新增 `controlsVisible` 透传；makeUIView 初次同步 + updateUIView 增量同步（占位 UIView 路径安全跳过）
- 调用点：`MpvVideoPlayerView.swift:68,73` 两处容器传入 `controlsVisible`
- **申报**：「淡入 0.15s 无掉帧」为肉眼/Instruments 验收项，无头环境无法自证，留待审查者真机复核

## 复现命令
```bash
xcodebuild build -project FryfrogHub.xcodeproj -scheme FryfrogHub -configuration Release \
  -destination 'generic/platform=iOS'
xcodebuild test -project FryfrogHub.xcodeproj -scheme FryfrogHub \
  -destination 'platform=iOS Simulator,id=1DE872C2-235F-4461-9923-C2B1513618D2'
```
