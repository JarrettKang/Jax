# Jax v0.2 开发计划

## 1. 文档信息

- 需求基线：`PRD.md`
- 历史基线：`Development_plan.md`、`Android_v0.1_Development_plan.md`
- 目标平台：Windows、Android
- 当前增量：F2.7：记录栏目层级统计
- 状态：F2 开发中
- 更新日期：2026-08-25

## 2. 统一执行规则

- 延续 Core + Data + UI、Local First、小步增量和 Windows/Android 共用业务规则及数据模型的原则。
- 每个功能先确定验收条件并添加有效测试，再做最小实现；新增测试和全部历史测试通过后，分别完成 Windows、Android Debug 验收和静态分析，最后创建独立 Git commit。
- 日常增量不生成 Release；不得删除或跳过测试、降低验收标准，也不得借当前功能重构无关模块。
- 产品行为变化最小更新 `PRD.md`，开发与验收过程记录在本计划；v0.1 开发计划保持为历史基线。

## 3. F1：首页

### 3.1 功能范围与验收条件

- Windows NavigationRail 和 Android/窄屏底部导航统一增加首项“首页”，启动默认进入首页，原事件、记录及全局保存能力保持可用。
- 首页依据设备当前本地时间显示 PRD 定义的五段问候语；全部边界使用注入式 Clock 确定性测试，并在进入、返回首页或跨越时间边界后刷新。
- 无 `running` 事件时显示可点击的“我们来做点什么？”，点击只进入事件栏目。
- 有 `running` 事件时只显示“当前正在执行：”及正确事件名称，不显示其他状态事件或额外快捷功能。
- start、pause、resume、complete 及应用恢复后，首页读取并反映事件系统的真实状态。

### 3.2 三层影响

- Core：增加轻量、无 Flutter 依赖且可注入时间测试的共享问候语规则。
- Data：复用现有 Event Repository 和 SQLite，不修改 schema、migration 或持久化语义。
- UI：增加共享 Home 页面；在现有宽屏 NavigationRail 和窄屏 NavigationBar 中增加入口，仅做必要响应式布局。

### 3.3 自动化测试

- Core：问候语全部时间边界及本地时间语义。
- UI：无/有 `running` 状态、点击跳转、只选择真正的 running 事件，以及 start/pause/resume/complete 状态同步。
- 响应式导航：首页 / 事件 / 记录顺序、默认首页、Windows 宽屏桌面导航、手机窄屏底部导航和大字体无 overflow。
- 回归：全部 Core、Data、Widget 与现有 Windows/Android 集成测试；运行 `flutter analyze`。

### 3.4 Debug 验收

- Windows：验证默认首页、当地问候、点击跳转、完整状态同步、原事件/记录/保存能力及正常关闭自动暂停规则。
- Android 模拟器：验证默认首页、三项底部导航、当地问候、完整状态同步、窄屏/大字体、返回行为、保存和既有生命周期规则。
- 只有共享组件的实际风险无法由 Widget 与模拟器覆盖时，才进行最小真机 Debug 验收；不得清除或破坏真机现有数据。

### 3.5 Git 与完成状态

- 文档、测试和实现作为 F1 完整功能提交，建议提交信息：`feat: add shared Jax home page`。
- 完成条件：全部自动化测试、静态分析和双端 Debug 验收通过，diff 无无关修改，独立提交后工作区干净。
- 当前状态：已完成。问候语边界、首页状态、响应式导航及全部历史自动化测试共 72 项通过；Windows Debug 集成测试、Android 模拟器 Debug 完整流程和 Android `sqflite` 契约测试均通过；`flutter analyze` 无问题。模拟器主程序人工可见性检查确认当地问候、三项底部导航和首页窄屏布局正常。F1 未修改 Data 或 SQLite schema，未执行 Release。

### 3.6 F1 UI 修复记录

- 2026-08-25：修复 Windows 默认字体发生中文逐字形 fallback、导致同一句文字视觉字重不一致的问题；Windows Theme 统一使用系统自带的 Microsoft YaHei UI，保留 Material 原有字号和字重层级，Android 继续使用平台默认字体。

## 4. F2：事件层级

### F2.1：层级数据模型与 migration

- 验收：Event 支持 nullable 直接上层 ID；schema v2→v3 后旧 Event 全部为顶级事件且事件、状态、时间和片段不变；Repository 可查询直接上层/下层并原子更新关系；Windows SQLite 与 Android sqflite 使用同一 schema。
- 测试：模型复制/相等、全新 schema、真实 v2 migration、外键、关系更新/解除、reopen 和 Repository 查询；运行全部历史测试及双端数据库契约。
- 当前状态：已完成。schema 由 v2 升级为 v3；新增 nullable `parent_event_id`、自引用外键、直接上层/下层查询和关系更新。真实 Windows v2→v3 migration、Android 模拟器 sqflite migration、reopen、外键、全部 76 项历史自动化测试、Windows Debug 集成与 Android SQLite 契约均通过；真机真实数据库未执行 migration。

### F2.2：层级 Core 规则

- 设置、移动、解除关系；自身/后代无环硬校验；事件/记录候选范围；有下层时删除保护。Core 与 Repository 双重校验并使用事务。
- 当前状态：已完成。Core 支持设置/移动/解除、无环与栏目状态候选规则；pending/completed 删除均保护直接下层；SQLite Repository 在事务内再次验证事件存在、状态组合和递归无环。全部 81 项自动化测试、静态分析、Windows Debug 集成及 Android 模拟器 sqflite 规则测试通过。

### F2.3：层级执行状态

- running 切换到后代时自动暂停并开始/恢复后代；未完成祖先转 paused；其他方向仍阻止；下层完成不恢复上层；层级完成规则和单 running 回归。
- 当前状态：已完成。running 可原子切换到任意深度的 pending/paused 后代，原开放片段关闭、目标新片段开启且所有未完成祖先转 paused；无关、祖先及其他非法方向继续阻止，失败操作不消耗 ID。下层完成不自动恢复上层，父层完成受未完成直接下层保护。全部 91 项自动化测试、静态分析、Windows Debug 完整工作流、Android 模拟器 v2→v3/sqflite 切换契约及 Android Debug 完整工作流通过；真机真实数据库未参与测试。

### F2.4：层级时间统计

- 直接执行时间、任意深度总投入聚合及防重复计算；移动层级后即时重算，不创建重复片段。
- 当前状态：已完成。共享 Core 服务以同一注入 Clock 计算 Event 自身全部片段的直接时间，并递归逐节点汇总任意深度后代，使用已访问集合防止重复计算；层级移动后从 Repository 关系即时重算，不缓存、不新增片段。全部 95 项自动化测试、静态分析及 Windows/Android 模拟器 Debug 完整工作流通过；Data、schema 和 migration 未改变。

### F2.5：事件栏目层级 UI

- 共享逐层详情、上下层查看与关系编辑、候选过滤、移动确认、解除关系；Windows 宽屏、Android 窄屏、大字体和长名称验收。
- 当前状态：已完成。事件卡片提供共享层级详情入口，可逐层进入直接上层/下层，设置或解除上层、添加已有 Event 为下层；移动已有关系时明确确认，候选复用 Core 过滤规则，关系修改继续自动持久化。97 项自动化测试、静态分析、Windows 与 Android 模拟器 Debug 完整工作流通过；320px 窄屏、1.5 倍字体和长名称无 overflow，未复制平台专用页面。

### F2.6：首页层级上下文

- running Event 有有效上下文时显示直接上层和同级 Event；顶级或无有效同级时保持 F1 首页。
- 当前状态：已完成。首页从每次 Repository reload 得到 running Event 的直接上层和其他同级；仅在同时存在直接上层及至少一个其他同级时显示，上下文不足时严格保持 F1。99 项自动化测试、静态分析及 Windows/Android 模拟器 Debug 完整工作流通过；未新增持久化状态或平台专用 UI。

### F2.7：记录栏目层级统计

- 记录首页最高 completed 节点过滤；详情展示总投入、直接时间和下一层总投入；支持逐层浏览与 completed 层级调整。

### F2.8：v0.2 全量验收

- 运行静态分析、全部 Core/Data/Widget/Windows/Android 集成测试；完成 Windows Debug、Android 模拟器 Debug、v2→v3 migration 和必要的经授权真机轻量验收。仅形成稳定 Debug 基线，不生成 Release。

### F2 统一提交与数据安全

- F2.1–F2.7 每项均测试先行、全量回归、双端 Debug 验证、独立 commit 后再继续。migration 先在临时库、Windows 和 Android 模拟器验证；未经单独确认不得在真机真实数据库升级。
- 额度不足时优先停在测试通过、已提交且工作区干净的增量边界；若中途暂停则维护 `CODEX_RESUME.md`，准确记录测试、schema、migration、Git、平台进程和恢复后的第一个具体动作。
