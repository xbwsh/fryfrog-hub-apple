# 新需求任务单 — 播放页控件唤起卡顿修复

> 日期: 2026-08-22  
> 需求名: `playback-controls-fix` (分支 `feat/playback-controls-fix`)  
> 基线: `refactor-phase3-pass` (82485a5)  
> 复现: 点击画面唤起控件固定延迟 ~300ms，体感卡  
> 根因: `MpvVideoPlayerView.swift:122` 双击/单击 `exclusively` 仲裁 + 主线程 Metal 渲染争抢（见上一轮排查）  
> 负责人: Executor (单人串行)  
> 复现模拟器: `1DE872C2` (FryfrogHub-Test iOS 26.5)

## 目标

单击立即唤起/隐藏控件（<50ms），双击仍能暂停/播放，长按/拖动等手势不回归。

## 任务分解（串行，不可并行）

| 顺序 | ID | 标题 | 文件 | 工时 | 验收 |
|---|---|---|---|---|---|
| 1 | T4-1 | 手势仲裁重构：消除单击 300ms 延迟 | `FryfrogHub/Views/Player/MpvVideoPlayerView.swift:119-145` | 0.5d | 单击 `toggleControls()` 无延迟（时间戳自判或 UIKit `require(toFail:)` 且 `delaysTouchesBegan=false`）；双击 `togglePlay()` 仍可用；拖动/长按 2x 不误触；`xcodebuild build` 0 warning |
| 2 | T4-2 | 主线程让路：动画期间不被渲染挤掉帧（可选，若 T4-1 后仍掉帧再做） | `MpvMetalView.swift:109,164` `MpvVideoPlayerView.swift:358-381` | 0.5d | `tick` 的 `renderFrame` 放后台或 `controlsVisible` 时 `preferredFramesPerSecond=30`；Instruments 或肉眼：控件淡入 0.15s 无掉帧；`xcodebuild test` 15/15 |

**依赖:** T4-2 依赖 T4-1；若 T4-1 后已流畅，T4-2 可与 Leader 确认后跳过。

## 门禁

- 每 T 独立 commit，`feat/playback-controls-fix ^..HEAD` 可按 commit 粒度分别评审
- 本地提交即可提审（无远端）：提审区间以 `git log --oneline refactor-phase3-pass..HEAD` 为准
- 需 `REVIEW_PASS` 带 `file:line` 才可合入 `main`，`max_rework=2`

## 分支操作（无远端，本轮本地）

```bash
git checkout refactor-phase3-pass
git checkout -b feat/playback-controls-fix
# ... 按 T4-1、T4-2 串行提交 ...
git log --oneline refactor-phase3-pass..HEAD  # 提审区间
```

有远端后再 `git remote add origin <url> && git push -u origin feat/playback-controls-fix`，不阻塞本轮。
