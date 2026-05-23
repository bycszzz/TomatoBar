# 番茄记录 + 进度看板 + 项目复盘 — 实施方案

> 退出 plan 模式后第一步：把本文件内容原样复制到仓库内 `docs/feature-tracking-plan.md`（plan 模式仅允许编辑当前文件，故先落在这里）。

## Context

TomatoBar 现仅把状态转换以 JSON 行追加到沙盒 Caches 下的 `TomatoBar.log`，没有项目维度、没有聚合视图，长期复盘只能 `jq` 手抠。本次新增：

- **项目 / 区域** 两层归类（区域为可选子层）。
- **Session 持久化**：每个 work（完成 / 放弃）和 rest 段都落盘。
- **看板**：今日/本周/本月数字概览 + GitHub 风格热力图 + 周/月柱状（Apple Charts）。
- **项目复盘**：完成态项目展示总时长、区域分布、小时热力、累计曲线。

目标用户故事覆盖：CPTS 长期备考多区域归类、日常多项目快速切换、长期回顾。

## 已确认的关键决策

| 项 | 决策 |
| --- | --- |
| 存储 | JSON 文件（`Codable`），沙盒 `Documents/tracking.json` |
| Session 粒度 | 完成 work / 放弃 work / rest 段 三类都记；`addMinute` / `skip` 不单独记录，体现在 session 的 `actualDuration` 与 `completed` 字段 |
| 未指定项目 | `projectId` 允许为空；看板可单独过滤"未分类" |
| 图表 | Apple Charts 框架；部署目标提到 **macOS 14.0**（用户 macOS 26 无影响） |
| 状态机 / 计时器 | **不重构**，只在 transition handler 末尾追加调用 |
| URL Scheme | 行为不变 |
| 新增依赖 | 无（不引入 GRDB / 第三方图表库） |

## 方案概览

最小化新增模块、零新依赖：

1. 新增 `Tracking/` 子目录承载数据层（`Models.swift` + `TrackingStore.swift`），`TrackingStore` 仿照现有 `logger` / `TBStatusItem.shared` 模式做成 shared 单例，`ObservableObject` 供 SwiftUI 绑定。
2. 在 `TBTimer` 的现有 `onWorkStart` / `onWorkEnd` / `onRestStart` / `onRestEnd` 这些 handler 里**追加几行**：进入 work/rest 时记一个 `sessionStartTime` 与当前 `currentProjectId`，离开时往 `TrackingStore` append 一条 `Session`；`work → idle` 通过区分触发事件（`startStop` vs `timerFired` vs `skipEvent`）判定 `completed`。
3. UI 分两块：
   - `TBPopoverView` 顶部加项目/区域 picker（小，复用现有 Popover），不破坏当前布局。
   - 看板独立 `Window` scene，在 `TBApp.body` 里和 `Settings {}` 并列声明，菜单栏 popover 加一个"打开看板"按钮，用 `@Environment(\.openWindow)` 触发。
4. 项目/区域 CRUD：放在看板窗口的侧栏（不再单开窗），保持菜单栏极简。

## 数据存储选型（含理由与取舍）

**结论：JSON 文件**。位置 `~/Library/Containers/<BundleID>/Data/Documents/tracking.json`（沙盒 Documents，用户也可手动备份/编辑/`jq`）。

| 方案 | 优 | 劣 | 评 |
| --- | --- | --- | --- |
| **JSON（采用）** | 零依赖；可读可手改；1k session ≈ 200KB 全量加载零压力 | 万级以后聚合慢、需要内存全量 | 个人 5 年使用预估 < 10k session，完全够 |
| SwiftData | 原生、查询语义好 | 与现有手写 Codable 持久化风格不一致、调试要 schema 迁移；为这点查询量上 ORM 过重 | 拒 |
| GRDB / SQLite | 查询/聚合强 | 新增第三方依赖（违反默认约束）；SQL 代码量 > JSON 实现 | 拒 |
| 复用现有 `TomatoBar.log` | 不开新文件 | append-only NDJSON 与结构化 CRUD 数据语义冲突；项目/区域的修改无法 in-place | 拒 |

**持久化细节**：

- 单文件结构：`{ "projects": [...], "areas": [...], "sessions": [...] }`。
- 写入策略：`TrackingStore` 持内存副本，每次变更后 `Data.write(to:options: .atomic)` 整文件覆写。1k session JSON 序列化 + 原子写 < 5ms，对每 25 分钟一次的频率完全 OK。
- 加载：app 启动一次性读入。
- 备份位：每次启动时把上一次的 `tracking.json` 复制为 `tracking.json.bak`，最小化崩溃 + 写半的风险。

## 架构变更（文件清单）

### 新增

| 路径 | 职责 |
| --- | --- |
| `TomatoBar/Tracking/Models.swift` | `Project` / `Area` / `Session` 三个 `Codable, Identifiable` struct，含枚举 `ProjectStatus { active, completed, archived }` 与 `SessionType { work, rest }` |
| `TomatoBar/Tracking/TrackingStore.swift` | `final class TrackingStore: ObservableObject`，`static let shared`，提供 `appendSession / upsertProject / upsertArea / archive / complete / sessions(in:projectId:)` 等；负责 JSON 加载/原子写/.bak 备份 |
| `TomatoBar/Tracking/Aggregations.swift` | 纯函数：日聚合 / 周聚合 / 月聚合 / 项目分布 / 小时分布；输入 `[Session]`，输出绘图友好结构。无状态，便于以后单测 |
| `TomatoBar/View/ProjectPicker.swift` | 顶部 picker（当前项目 + 区域 + "+新建"）；嵌入到 `TBPopoverView` |
| `TomatoBar/View/Dashboard/DashboardWindow.swift` | `View`，看板顶层容器：左侧项目列表，右侧今日/周/月切换 + 概览 + 热力图 + Charts |
| `TomatoBar/View/Dashboard/HeatmapView.swift` | GitHub 风格 7×~52 网格热力图，颜色阶 5 档；按项目过滤、按日期范围切片 |
| `TomatoBar/View/Dashboard/WeeklyBarChart.swift` | Apple Charts 周视图（按天） |
| `TomatoBar/View/Dashboard/MonthlyStackedChart.swift` | Apple Charts 月视图，按项目堆叠 |
| `TomatoBar/View/Dashboard/ProjectRetroView.swift` | 完成态项目复盘：总时长 + 区域饼图 + 小时热力 + 累计曲线 |

### 修改

| 路径 | 修改要点 |
| --- | --- |
| `TomatoBar/Timer.swift` | 加 `currentProjectId: UUID?` / `currentAreaId: UUID?` 两个 `@AppStorage` 字段；加私有 `sessionStartTime: Date?` 与 `sessionPlannedDuration: Int`；在 `onWorkStart` / `onRestStart` 记录开始；在 `onWorkEnd` / `onRestEnd` 调用 `TrackingStore.shared.appendSession(...)`；用触发事件区分 `completed` |
| `TomatoBar/View.swift` | 顶部插入 `ProjectPicker`；底部加"打开看板"按钮；其余布局不动 |
| `TomatoBar/App.swift` | `TBApp.body` 增加 `Window("Dashboard", id: "dashboard") { DashboardWindow() }`；处理 `LSUIElement` 风格下窗口激活（`NSApp.setActivationPolicy(.regular)` 临时切换 + 关闭时回 `.accessory`） |
| `TomatoBar.xcodeproj/project.pbxproj` | `MACOSX_DEPLOYMENT_TARGET` 12.0/12.3 → 14.0 |
| `TomatoBar/*.lproj/Localizable.strings` | 新增 picker / dashboard / retro 用到的字符串，每语种同步占位 |

### 不动

- `State.swift`、`Notifications.swift`、`Player.swift`、`DND.swift`、`Log.swift`、`MaskView.swift`、`TomatoBar.entitlements`、`Info.plist`（URL Scheme 保持）。
- `.github/workflows/main.yml`（自用，CI 当只读参考）。

## 里程碑拆分

每个里程碑独立可提交、可验收，不依赖下一步即可单独使用。

### M1：数据层 + 静默落盘（无 UI 变化）

- 落地 `Tracking/Models.swift` 与 `Tracking/TrackingStore.shared`。
- 在 `TBTimer` 现有 handler 末尾接入 `appendSession`。
- `currentProjectId` 暂留 nil，全部 session 走"未分类"。
- 升 `MACOSX_DEPLOYMENT_TARGET` 到 14.0。

**验收**：
- 跑 3 个完整 work + 2 个 rest + 1 次中途 stop，查 `~/Library/Containers/.../Documents/tracking.json` 能看到 6 条 session：3 条 `type=work, completed=true`、1 条 `type=work, completed=false`、2 条 `type=rest, completed=true`，`actualDuration` 与 `plannedDuration` 在合理范围。
- 重启 app，文件不丢、不被截断。

### M2：Popover 项目选择器 + 项目/区域 CRUD

- `ProjectPicker` 接入 popover 顶部，能选 / 新建 / 删除 / 归档项目与区域。
- `currentProjectId` / `currentAreaId` 经 `@AppStorage` 持久化。
- 后续记录的 session 带上 ID。

**验收**：
- 新建项目 P1 含区域 A1/A2，切到 P1+A1 跑一个番茄，session 的 projectId/areaId 写入正确。
- 切回未分类，新番茄的 projectId/areaId 为 nil。
- 删除项目时弹确认，所属 session 不删除，projectId 失效后视为"未分类"。

### M3：看板窗口骨架 + 数字概览 + 热力图

- 新 Window scene + 菜单栏"打开看板"入口 + 激活策略切换。
- 顶部三张数字卡（今日/本周/本月：番茄数 + 专注时长）。
- GitHub 风格热力图（默认近 53 周），可按项目下拉过滤。

**验收**：
- 用脚本注入 1500 条 mock session，热力图首屏渲染 < 200ms，滚动/切项目无卡顿。
- 关闭看板窗口后 app 回到 menu-bar-only 状态，Dock 图标消失。

### M4：周 / 月 Charts

- `WeeklyBarChart`：本周 7 天，每天专注分钟柱状。
- `MonthlyStackedChart`：本月按项目堆叠。
- 与上方项目过滤联动。

**验收**：
- 切项目过滤，柱状与热力图数据一致（同一份 `Aggregations` 输出）。
- 周/月切换无重新加载延迟。

### M5：项目复盘视图 + 完成态

- 项目可标记"完成"，标记后看板里项目列表显示完成时间。
- 点完成态项目进入 `ProjectRetroView`：总时长、区域分布饼图、24h 小时热力、累计专注曲线。

**验收**：
- 把 mock 项目设为完成，复盘视图四个组件全部正确反映 mock 数据。
- 把项目从完成改回 active，复盘入口消失但数据不丢。

## 风险点（Top 3）

1. **Session 开始时刻的统计含暂停时间 → `actualDuration` 偏长**
   - 现有 `pauseResume()` 用 `pausedTimeRemaining` 维护剩余时间，但没有"已过去时长"概念。
   - **对策**：在 `TBTimer` 加 `accumulatedActiveDuration: TimeInterval`，进入 work/rest 时归零，每次 pause 时累加 `now - lastResumeTime`，resume 时重置 `lastResumeTime`；结束时 `actualDuration = accumulatedActiveDuration + 当前活跃片段`。这样 `actualDuration` 反映"实际计时跑了多久"，与 `plannedDuration`（来自 preset）的差就是用户使用 `addMinute` / `skip` / pause 的净效应。

2. **菜单栏 app 弹独立 Window 的激活策略**
   - 当前 `TBApp` 只有 `Settings {}`，行为像 accessory app；直接加 `Window {}` 在 Dock 不显图标、`Cmd+Tab` 选不到，用户体验崩。
   - **对策**：打开 dashboard 前 `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)`；监听窗口 `willClose` 事件，关闭后 `NSApp.setActivationPolicy(.accessory)` 回到 menu-bar-only。Settings 窗口也走同套逻辑（如果之前没碰过，行为可能本来就一致）。

3. **写盘频率叠加 pause/resume 状态机抖动，可能写半 / 顺序错**
   - Handler 都在主线程，整文件原子覆写本身无并发问题；但若以后接入命令行/URL 触发的批量动作，会出现"短时间多次写入"。
   - **对策**：`TrackingStore` 内部用 `private let queue = DispatchQueue(label: ..., qos: .utility)` 串行化 IO；公开 API 同步返回（仅内存更新），异步落盘；exit 时 `applicationWillTerminate` 里 `queue.sync {}` 等一次 flush。再加启动时 `.bak` 备份兜底。

## 第一步入口任务（切到 Sonnet 后第一条 prompt）

```
执行 docs/feature-tracking-plan.md 的 M1（数据层 + 静默落盘）。具体：
1. 新建 TomatoBar/Tracking/Models.swift，含 Project（id/name/status/createdAt/completedAt?）、
   Area（id/projectId/name）、Session（id/projectId?/areaId?/startedAt/endedAt/
   plannedDuration/actualDuration/type/completed/notes?）三个 Codable+Identifiable struct，
   配套枚举 ProjectStatus 与 SessionType。
2. 新建 TomatoBar/Tracking/TrackingStore.swift：final class TrackingStore: ObservableObject，
   static let shared，沙盒 Documents/tracking.json 加载 + 原子写 + 启动时 .bak 备份；
   公开 appendSession / upsertProject / upsertArea / sessions(in:projectId:) 等同步 API，
   内部用 utility 串行 queue 异步落盘。
3. 改 TomatoBar/Timer.swift：加 sessionStartTime / sessionPlannedDuration / accumulatedActiveDuration
   私有字段；在 onWorkStart/onRestStart 抓 Date()；onWorkEnd/onRestEnd 调 appendSession；
   通过 transition context 区分 completed 标志（startStop → false；timerFired/skipEvent → true）。
4. TomatoBar.xcodeproj：MACOSX_DEPLOYMENT_TARGET 改 14.0（两处 build configuration 都改）。

不动 UI、不动状态机路由、不引入新依赖。完成后跑 5 个番茄手动验证 tracking.json
（参考 docs 的 M1 验收节）。
```

## 验证 / 回归

- 每个里程碑跑 README 提到的 `tomatobar://startStop` / `pauseResume` / `skip` / `addMinute` 各一次，确认 URL Scheme 行为未变。
- M1 完成后再跑 SwiftLint：`swiftlint`，无新增 warning。
- 看板上线后用脚本注入 mock session 测千级渲染：
  ```bash
  # 占位，M3 里再具体提供脚本
  swift run mock-tracking 1500
  ```
- 每个里程碑独立 commit，便于回退。
