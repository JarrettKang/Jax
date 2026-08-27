# Jax v0.2 开发计划

## 1. 文档信息

- 需求基线：`PRD.md`
- 历史基线：`Development_plan.md`、`Android_v0.1_Development_plan.md`
- 目标平台：Windows、Android
- 当前增量：F4：事件操作区整理与恢复 completed Event
- 状态：F4 已完成
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
- 当前状态：已完成。记录首页仅显示无上层或上层尚未 completed 的最高已完成节点；详情显示当前节点总投入、直接执行时间、直接下层及各自总投入，并可逐层进入任意深度和打开既有 completed 层级调整。100 项自动化测试、静态分析及 Windows/Android 模拟器 Debug 完整工作流通过，窄屏操作无回归。

### F2.8：v0.2 全量验收

- 运行静态分析、全部 Core/Data/Widget/Windows/Android 集成测试；完成 Windows Debug、Android 模拟器 Debug、v2→v3 migration 和必要的经授权真机轻量验收。仅形成稳定 Debug 基线，不生成 Release。
- 当前状态：已完成。100 项 Core/Data/Widget 自动化测试和 `flutter analyze` 全部通过；Windows v0.1 与 v0.2 临时 SQLite 集成、Android `sqflite` 契约、v2→v3 migration、Android v0.1 与 v0.2 临时 sqflite 集成全部通过。Windows/Android 均使用 Debug，F2.1–F2.7 已逐项独立提交；未修改 schema（当前 v3）、未对真机真实数据库执行 migration，未生成 Release。F2.8 形成稳定 Debug 基线。

### F2 统一提交与数据安全

- F2.1–F2.7 每项均测试先行、全量回归、双端 Debug 验证、独立 commit 后再继续。migration 先在临时库、Windows 和 Android 模拟器验证；未经单独确认不得在真机真实数据库升级。
- 额度不足时优先停在测试通过、已提交且工作区干净的增量边界；若中途暂停则维护 `CODEX_RESUME.md`，准确记录测试、schema、migration、Git、平台进程和恢复后的第一个具体动作。

## 5. F3：同级事件排序

- F3 延续 Core + Data + UI、Windows/Android 共用模型、Local First、Debug 优先和每个增量独立测试/回归/提交规则；不生成 Release，不连接真机。
- F3.1：排序数据模型与 v3→v4 migration，使用 `created_at_utc + id` 为旧数据建立稳定初始顺序，并提供有序查询。
- F3.2：Core/Repository 同级重排序、新建末尾、层级移动/解除后进入新集合末尾及原子事务。
- F3.3：事件与记录页面的共享排序入口、逐层有序展示和窄屏/大字体适配。
- F3.4：首页同级列表按用户定义顺序展示，状态仍来自现有 Event。
- F3.5：全量测试、Windows/Android Debug、migration 和回归验收；完成后形成稳定 Debug 基线，不生成 Release。
- 当前状态：F3.1 开始前，F2.8 已完成，schema 当前为 v3，Android 真机真实数据库不参与 migration。
- F3.1 状态：已完成。新增 `sort_order` 模型字段和 v3→v4 migration；旧 v2→v4 数据按 `created_at_utc + id` 建立稳定初始顺序，顶级及任意上层下的同级查询按该顺序返回，reopen 后保持。101 项自动化测试、静态分析、Windows Debug 回归和 Android 模拟器 migration 通过；真机未连接、未执行 migration。
- F3.2 状态：已完成。Core `ReorderSibling` 与 SQLite/Memory Repository 支持同级内部重排；新建、换上层和解除上层在目标集合末尾，排序与 hierarchy 通过事务一致更新，状态/层级/执行事实不被重排改变。107 项自动化测试、静态分析、Windows Debug 回归和 Android 模拟器 sqflite migration/排序验收通过。
- F3.3 状态：已完成。事件页、记录页及记录详情复用共享排序控制，逐层展示同级顺序；新增上移/下移操作不改变状态、层级或执行事实，并覆盖窄屏与大字体布局。109 项自动化测试、`flutter analyze`、Windows Debug 层级工作流和 Android 模拟器 Debug 层级工作流通过；未修改 SQLite schema，真机未连接。
- F3.4 状态：已完成。首页复用现有有序 Repository 同级查询展示上下文，同级事件名称保持用户定义顺序，未增加首页专用状态或数据；新增首页顺序 Widget 测试通过。110 项自动化测试、`flutter analyze`、Windows/Android Debug 回归通过；未修改 SQLite schema，真机未连接。
- F3.5 状态：已完成。全量 110 项 Core/Data/Widget 自动化测试、`flutter analyze`、Windows v0.1/v0.2 Debug 工作流、Android 模拟器 v0.1 工作流及 v2→v4 sqflite migration/排序回归全部通过；schema 当前为 v4，未连接或修改 Android 真机，未生成 Release。F3 形成稳定 Debug 基线。

## 6. F4：事件操作区整理与恢复 completed Event

- F4.1：事件卡片常驻状态相关操作及可连续执行的同级排序快捷按钮；层级、编辑和删除移入按现有规则动态显示的更多菜单。running 的暂停与完成须在视觉和空间上清晰区分。仅调整共享 UI，不修改 Core、Data 或 schema。
- F4.2：completed Event 可从记录栏目恢复为 paused，保留执行片段、层级与排序，不自动 running；必要的 completed 祖先在同一事务中同步恢复，completed 下层不递归恢复。
- F4 完成验收：全部自动化测试与静态分析、Windows Debug、Android 模拟器 Debug 及 F1/F2/F3 回归通过；不连接或迁移 Android 真机，不生成 Release。
- F4.1 状态：已完成。事件卡片常驻开始/恢复、明确区分的暂停与完成，以及仅在当前位置合法时显示的上移/下移快捷按钮；层级、编辑和合法删除进入动态更多菜单。父事件及 running Event 不显示非法删除，running 不显示编辑。115 项 Core/Data/Widget 自动化测试、`flutter analyze`、Windows v0.1/v0.2 Debug 工作流和 Android 模拟器 v0.1/v0.2 Debug 工作流通过；schema 仍为 v4，未连接真机，未生成 Release。
- F4.2 状态：已完成。记录栏目通过低频菜单和简短确认恢复 completed Event；共享 Core 将目标及连续 completed 祖先恢复为 paused、清除当前完成时间且不恢复下层、不启动计时、不影响 running，SQLite 在单事务内持久化整条恢复链并保留 run_segments、层级和排序。122 项 Core/Data/Widget 自动化测试、`flutter analyze`、Windows v0.1/v0.2 Debug、Android 模拟器真实 sqflite 契约及 v0.2 Debug 工作流通过；schema 仍为 v4，未连接真机，未生成 Release。

## 7. F6：世界分类

- F6.1 新增独立 `categories` 表和 root Event nullable `category_id`，schema 由 v5 升级到 v6；旧 Event 迁移后全部进入虚拟“未分类”，不创建系统 Category 记录。迁移必须保留 hierarchy、sort order、状态、run_segments 和历史事实，并在临时库及双端 Debug 验证。
- Category Core 规则包括名称校验、唯一名称、CRUD、独立排序、删除归还未分类、root assignment，以及 child→root 继承 / root→child 清除直接 category。World UI 只派生 descendants 的所属 Category，不复制 category_id。
- F6.2 测试策略新增 Category Core/Data/migration/World Widget 覆盖；继续执行完整自动化回归、`flutter analyze`、Windows Debug 和 Android Emulator Debug，真机不参与 migration，不生成 Release。
- F6.3 World presentation 改为 Category overview → Category detail 两层结构；overview 响应式展示派生的 Event/root 数量及 running Category 轻量状态，detail 原样复用高密度 hierarchy，并从当前 Category 上下文创建 root Event。旧 Category collapse preference 保留为兼容数据但不再参与 UI，不修改 schema。
- F4.3 状态：已完成。提交后 `flutter analyze` 和全部 122 项 Core/Data/Widget 自动化测试通过；Windows v0.1/v0.2 Debug 验收通过且普通 Debug 产物已恢复、无进程或文件锁残留；Android 模拟器 v0.1、真实 sqflite 恢复契约、v2→v4 migration 和 v0.2 层级/恢复 Debug 工作流全部通过。schema 保持 v4，未连接或修改 Android 真机，未生成任何 Release。F4 形成新的稳定 Debug 基线。

## 8. F7：日/周时间复盘

- F7.1：Core `TimeSummaryService` 以现有 run_segments 动态计算本地 23:00 日界线的日/周窗口 overlap，并按当前 root Category 聚合；不新增 summary 表或 schema。
- F7.2：记录栏目改为日总结/周总结；日视图使用 Category 横向时间条，周视图使用七日真实时长 Category 堆叠柱及周汇总。
- F7.3：completed 全量结构、层级与排序由 World 承担；恢复、投入详情和删除历史记录迁移到 World completed Event 菜单。
- F7 测试覆盖跨 23:00、跨周、open segment、多 Category/未分类、动态 Category 归属、零记录、周日合计，以及 Summary/World Widget 与双平台 Debug 回归。

## 9. F8：Routine / 日常

- F8.1：新增独立 Routine、RoutineExecution、RoutineRunSegment Core 模型与 RoutineRepository；recurrence 以枚举和 weekday bit mask 保存，今日 occurrence 使用本地 `YYYY-MM-DD`。
- F8.2：SQLite v6→v7 新增 routines、routine_executions、routine_run_segments；唯一约束保证同一 Routine 同一本地日期最多一个 execution，Category 使用 `ON DELETE SET NULL`。
- F8.3：SQLite transaction 统一 Event/Routine running slot，跨类型开始会关闭另一类型开放片段并暂停；Windows shutdown 同时处理两类 running，Android lifecycle 不改变既有语义。
- F8.4：TimeSummaryService 将 Event 与 Routine segments 归一到同一个 overlap/Category 聚合流程；不新增 summary 表或 category snapshot。
- F8.5：新增五栏导航“日常”、今日派生列表、创建/编辑 recurrence、开始/暂停/恢复/完成、停用/重新启用及首页 running Routine 简洁展示；World 保持纯 Event。
- F8 测试覆盖 recurrence、occurrence 唯一性、跨类型 running、segments、inactive/reactivate、Category 删除与动态历史、23:00 Summary、v6 migration、窄屏 UI、Windows/Android lifecycle 和完整回归。

## 10. F9：Today / 今日统一执行入口

- F9.1 抽取无 Flutter 依赖的 `JaxDay`，统一 Today、Routine recurrence 和 TimeSummaryService 的设备本地 23:00 日界线及显示日期 weekday。
- F9.2 schema v7→v8 新增 `event_day_plans(event_id, day_date, order_index, created_at_utc)`；复合主键防重复，Event 删除级联清理，旧数据库迁移后计划为空并完整保留 Event、Routine、Category、hierarchy、segments 与 execution。
- F9.3 Event Day Plan 使用独立 Repository；加入/移出/排序不修改 Event 事实。start/resume 和跨日 running Event 自动确保当前计划，completed 当天保留，running/completed 的移出受 Core/UI 保护。
- F9.4 原 Events page 重构为 Today presentation，分为当前 running 摘要、今日事项和今日日常；Event 使用独立 today order 与 breadcrumb，Routine 使用 definition order。World 接收 Event 创建、编辑、删除、hierarchy、Category、World order、恢复及今日规划入口；日常页保留 Routine 管理及备用执行能力。
- F9.5 跨日 running Routine 继续单一旧 execution，并覆盖当前日派生 occurrence，避免同名重复。Event/Routine 全局单 running、首页现在视角和 Record segment-only 统计保持不变。
- F9.6 测试包括 22:59/23:00/23:01、v7 migration、计划唯一性/移除/独立排序、World start 自动规划、completed 当天留存、waiting、weekday recurrence、跨日 running Routine、导航、空状态、长 breadcrumb、小屏与全部历史能力迁移；完成全量测试、analyze 和 Windows/Android Debug 验收后独立提交。
