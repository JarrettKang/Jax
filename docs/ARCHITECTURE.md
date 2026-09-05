# Jax v0.1 架构

## 分层与依赖

Jax 遵循 `UI → Core ← Data`。Core 不依赖 Flutter、SQLite 或具体平台；Windows 与 Android 复用 Core 的实体、状态规则、用例和 Repository/Service 接口。

- `lib/core`：事件、状态、执行片段、业务错误、Repository/Service 接口及用例。
- `lib/data`：共享 SQLite schema、Repository 和保存服务；平台入口为 Windows 选择 FFI/%APPDATA%，为 Android 选择 sqflite/应用私有目录。
- `lib/ui`：控制器、事件页、记录页和桌面应用壳。UI 只发起用例并展示结果，不自行修改状态。

## Local-first

业务写操作直接等待本地 SQLite 完成后才向 UI 报告成功。应用启动从 `%APPDATA%\Jax\jax.db` 加载完整数据，不依赖服务器。v0.1 没有服务器、账号或同步功能。

自动保存就是每次 Repository 写入的事务提交。全局手动保存调用同一数据库的 `SaveService.flush()`，执行 SQLite checkpoint，不创建第二份权威数据或备份文件。

## 正常关闭

应用通过 `AppLifecycleListener.onExitRequested` 处理 Windows 可取消退出请求。`PrepareForShutdown` 查找唯一的 running 事件，复用标准 `PauseEvent` 结束开放执行片段，然后调用 `SaveService.flush()`。操作成功才允许退出；失败则取消退出并提示重试。并发关闭回调共享同一个进行中的操作。

强制结束进程、系统崩溃和断电不属于 v0.1 的精确关闭保证。该退出监听只在 Windows 注册；Android 后台、锁屏、返回键和进程回收不映射为自动暂停，具体策略留待 Android v0.1 功能适配阶段确认。

## Planning P3.5 attention 与 P4 边界

当前长期结构由 `WorldNode` tree 承担，规划由 `Plan/PlanItem` 承担，`Event`
只承担扁平执行。World UI 与 Planning picker 都读取 WorldNode；Today/Home/Record
读取 Event 及 RunSegment，不再解释 Event parent/child。

Planned Event 只保存唯一 `sourcePlanItemId`，effective Category 在 Repository
查询时沿 Planning/WorldNode 关系动态推导；Standalone Event 保存 nullable direct
Category。Core Repository API 已移除 Event hierarchy、reparent、sibling reorder、
descendant switch 和 hierarchical completion。

WorldNode 同时拥有独立 lifecycle（`inProgress/completed`）和 attention
（`isFocused`）。Plan 仅拥有 `current/ended` 轮次状态。Planning Overview 的唯一
投影以 focused + inProgress WorldNode 为主体；current Plan 可以为空。关注切换只写
WorldNode，不结束 Plan、不修改 PlanItem 或任何执行事实。

Sync protocol 8 使用 dataset generation 隔离数据时代。旧协议层级字段只存在于
读取 protocol 1–3 baseline 的兼容转换中，转换后立即扁平化，当前 snapshot/apply
拒绝 legacy Event hierarchy mutation。

Today recommendation 由同一 Planning projection 根据 focused + inProgress
WorldNode、current Plan 和 next PlanItem 即时派生，不是数据库实体。Data 层在提交
时用同一资格条件再次校验。用户确认后，
`DispatchPlanItems → PlanningDispatchRepository` 将 Event insert、PlanItem
transition 与 EventDayPlan append 组合为一个事务。UI 不分别调用三个写 API。

planned Event 的 completion/restore coupling 放在 SQLite Event Repository 事务边界，
因此 waiting completion 与 running completion（包括关闭 open segment）都不会留下
Event/PlanItem 半提交状态。Today relation 仍是独立索引，移除/重加不改变
dispatch 事实。

PlanReviewNote 是 Plan 下独立的 appendable 业务实体。它不改变 Plan 状态、
PlanItem、Event 或 Record，只通过 PlanningRepository 写入；同步使用三方字段比较，
delete 产生 tombstone，apply 依赖顺序为 WorldNode → Plan → PlanReviewNote。

Recommendation Engine 位于 Core 的纯读派生层。Candidate Provider 从 Home 已有合法
Today Event/Scheduled Routine 投影生成稳定候选，Rule 只返回 signal，Engine
聚合为 Home 消费的 Recommendation。v1 TimeRule 只读 Routine 同步配置和
device-local clock；计算不触发 Repository 写入，不存储或同步推荐结果。

WorldNode Detail 是只读聚合层：当前/历史计划由 Plan 状态派生，执行历史只沿
`Event.sourcePlanItemId → PlanItem → Plan → exact WorldNode` 反查。它不聚合子节点，
不纳入 standalone Event，也不提供执行控制。
