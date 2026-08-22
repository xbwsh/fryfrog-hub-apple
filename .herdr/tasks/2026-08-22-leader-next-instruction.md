# Leader 下一步指示 — 基于评审单 + 执行者交付

> 日期: 2026-08-22  
> 输入: `.herdr/reviews/2026-08-22-fryfroghub-refactor-review.md` (Reviewer ✅通过) + `.herdr/modified/2026-08-22-refactor-phase0-2.md` (Executor 9提交 9e8c79b..c1d4449)  
> 角色: Leader (Muse Spark) — 只做裁决与分派，不直接改代码

## 一、裁决

**Phase 0-2 + T3-4/T3-5 有条件通过，准予合并。**

- 核心风险已闭环: `AsyncSemaphore.swift:9` 挂起式限流 / `MpvPlayer.swift:417-483` 事件线程解码前移消除悬垂指针 / `MpvMetalView.swift:38-50` 可失败初始化，三项均获 Reviewer ✅
- 拆分 20 文件抽查纯搬运，无逻辑漂移
- 已知偏差接受：
  - `MusicNowPlayingView.swift:1` 708行 / `MpvVideoPlayerView.swift:1` 1280行 / `SeriesDetailView.swift:1` 851行 未达 <300 行验收线 — 理由成立（单 struct 强耦合 @State，强拆必改状态流），按 Executor 申报保留整体，后续仅当状态抽至 ViewModel 时再拆
  - `MusicService.swift:9` 未加 `@MainActor` — Reviewer 建议非阻塞，`setStar:122` 已用 `MainActor.run` 包裹，暂不返修

**不通过项（转下一轮）:** `T3-1` 协议抽象 / `T3-2` 单测 target / `T3-3` try? 日志 — 三项未实施，Executor 已主动申报，不视为本次缺陷，但不得视为已完成

## 二、立即动作 (单执行者, 0.5d)

1. **收敛评审资产**
   - `git add .herdr/reviews/2026-08-22-fryfroghub-refactor-review.md .herdr/tasks/2026-08-22-fryfroghub-refactor-tasks.md .herdr/tasks/2026-08-22-leader-next-instruction.md .herdr/modified/2026-08-22-refactor-phase0-2.md`
   - commit: `docs(review): 收敛 Phase0-2 评审单与 Leader 指示`
   - 确认 `.gitignore` 未误忽略 `.herdr/`（当前未忽略，`git status` 显示 untracked 属正常）

2. **打 Tag**
   - `git tag refactor-phase2-pass && git log --oneline -9` 留档

## 三、下一轮任务单 (Phase 3 补齐, 单执行者串行, 优先级 P1)

> 约束变更：仅 1 名执行者，取消并行，按依赖串行执行，禁止在同一分支混改已通过文件。原 Executor-A/B/C 统一为 Executor。

| 顺序 | ID | 标题 | 负责人 | 工时 | 验收 |
|---|---|---|---|---|---|
| 1 | T3-1 | `APIClient`/`ServerConnection` 协议抽象 + 构造注入 | Executor | 1d | 新增 `APIClientProtocol`/`ServerConnectionProtocol`，`Networking/*Service.swift` 5 个类改 `init(client:server:)`，保留 `static let shared` 兼容；`grep -r "APIClient.shared" --include="*.swift" FryfrogHub` 仅兼容入口，`xcodebuild build` 0 warning |
| 2 | T3-2 | 关键路径单测 | Executor | 1d | 新增 `FryfrogHubTests` target，覆盖 `APIClient.swift:54` fallback / `APIClient.swift:173` `isConnectionFailure` / `APIConfig.swift:158` `probeLAN/refreshActiveMode` / 401/403 handler，`xcodebuild test` 通过 |
| 3 | T3-3 | 90 处 `try?` 接 `os.Logger` 分类 | Executor | 0.5d | `Logger(subsystem:"com.fryfrog.hub", category:"networking|image|storage")`，保留 `try?` 但落 `warning/error`，Console 可过滤 |
| 4 | T3-6 | `MusicService` @MainActor 收敛 (Reviewer 建议) | Executor | 0.5h | 类标注 `@MainActor` 或全部状态方法包裹 `MainActor.run`，消除 `loadHome/reload/loadSongs` 潜在竞态；`MusicService.swift:9` 为证据行 |

**执行顺序（串行，不可并行）:** T3-1 → T3-2 (依赖 T3-1) → T3-3 → T3-6  
**合计:** 2.5d+（单人串行，原 3 人并行 1.5d）

**门禁:** 每完成一项即交 Reviewer 只读审查，需 `REVIEW_PASS` 带 `file:line` 证据才可进入下一项；`max_rework=2` 超限 Leader 接管；单执行者不得跳序

## 四、明确不做

- 不再追求 `MusicNowPlayingView` 等 3 文件 <300 行硬指标
- 不新增第三方依赖（如 `AsyncAlgorithms`）— `AsyncSemaphore.swift:9` 已自研满足需求
- 不扩大 `build/` 产物提交范围

## 五、Leader 最终指令（单执行者版）

1. Executor 先执行 二-1 收敛资产并打 Tag
2. 串行执行 三：`T3-1` → Reviewer 审 → `T3-2` → Reviewer 审 → `T3-3` → Reviewer 审 → `T3-6` → Reviewer 审，严禁并行或跳序
3. 全部 `REVIEW_PASS` 后 Leader 作最终验收并关闭本轮重构

> 有异议 24h 内在评审单追加轮次，未异议即按此执行
