# Paused 直接完成

## 原行为审计

Planned / Standalone Event 共用 EventStatus；Scheduled / OnDemand Routine 共用 RoutineExecutionStatus。普通暂停、切换执行、修正暂停时间均会产生 paused 并关闭当前段。

原 `CompleteEvent` 只允许 running / waiting，故两类 paused Event 都被 domain guard 拒绝。Today Event 行仅展示恢复，Home Work 也只有继续。相反，`RoutineService.complete` 已可在没有 open segment 时直接更新 execution，Today paused Routine 本来就有恢复与完成；日常页 OnDemand 只有恢复，Scheduled 行只提供配置菜单。因此差异同时来自 domain 与页面 eligibility，并非 Planned 或 Routine 类型存在业务差异。

Event running 完成必须有 open segment；waiting 完成只更新状态。Routine 完成有 open 则关闭，否则仅更新状态。正常 paused 不应有 open；Sync readiness 也检查状态/open 对应，但没有要求 paused 必须有历史段，导入/历史删段后可以没有段。

Home 的修正时间菜单只针对 running；Record 与 World 详情提供历史展示/记录编辑，不是另一个执行状态菜单，也没有独立 Event Detail 执行器。日常编辑对话框只编辑 Routine 配置。

## 能力与写入

新增 `execution_capabilities.dart`，EventStatus / RoutineExecutionStatus 共享 canResume、canComplete 的定义。各自仍使用原有 `CompleteEvent` / `RoutineService.complete`，没有跨对象重建执行模型。

| 状态 | 开始 | 恢复 | 暂停 | 等待 | 完成 |
|---|---|---|---|---|---|
| Event pending / Routine 尚无 execution | ✓ | — | — | — | — |
| running | — | — | ✓ | ✓ | ✓ |
| paused | — | ✓ | — | — | ✓ |
| waiting | — | ✓ | — | — | ✓ |
| completed execution | — | — | — | — | — |

OnDemand 下一次“开始”是新 execution，沿用原规则。未启用 Routine 的恢复仍服从现有启用规则。

paused 完成只把 owner 设为 completed，completedAt / updatedAt 取确认时刻。没有创建或改写任何 RunSegment。Event 返回的 CompletedRecord 按原段合计主动时长；Routine/Record 仍按原段聚合。

Planned Event 的 `updateEvent` 事务保留 `_markLinkedItemDone`，所以即使源 Plan ended、WorldNode unfocused，也会完成原 PlanItem。Routine 按原 execution id 更新 occurrence，不重新选择今天的 occurrence。

仓储 update 方法新增可选 expectedPaused 参数：paused 完成时事务内验证原 owner 仍 paused、updatedAt 一致且无 open 段；Routine 的存储 waiting 标志也必须为 0。服务层也拒绝 paused + open 的异常数据，不修复或制造区间。已同步完成的对象再次提交会失败；Routine 还检查传入 paused execution 与重读状态/修订一致。PlanItem 联动失败时整个 Event 写入回滚。

## UI 与推荐

- Today paused Event 增加完成，保留恢复。
- Home Work paused Planned Event 增加轻量完成按钮，保留继续；成功后由 EventController reload 更新 action view。
- 日常页原 More 菜单在 paused 时提供恢复/完成，Scheduled 与 OnDemand 一致；原配置入口保留。
- Controller 读取并保留全部 paused Routine executions。Today 持续事项按 execution id 展示 `PausedRoutineRow` 的恢复/完成，超过 latestEnd、跨日甚至不在当天 recurrence 也不会失去入口。
- 原 occurrence 不再同时投影为“未开始推荐”。Home temporal 查询与旧 Recommendation Engine 都抑制 paused Routine；完成后移除原 paused 行，下一 occurrence 仍可按自己的真实生命周期出现。没有修改 Temporal 的四个状态或时间边界。
- 不新增 Home 的 paused 清单，Home 原本不展示的 Standalone/Routine 仍在 Today 管理。Record/World 历史视图保持只读状态展示。

## 数据、Sync 与测试

schema 24、Sync protocol 11 不变；无新字段、确认流程、假执行段或历史时间修正。running/waiting 的原执行路径与 resume 冲突规则保留。

新增数据测试覆盖四类对象的 10:00–10:30 执行、11:00 确认完成，原段整行不变；两个方向各执行 snapshot→compare→compile→apply，验证状态、completedAt、原段与 PlanItem done 的 business fingerprint。包含 ended Plan / unfocused node、零历史段、异常 open、过期提交和联动失败回滚。

双平台 widget 测试覆盖 Today 的两类 Event、两类 Routine，日常 More 和 Home Work 的直接完成；Routine 在次日已过推荐窗口仍可完成原 execution，完成前不会重复出现“开始”推荐。

真实用户数据库未用于完成或同步实验，此轮不自动安装真机。

## 最终验证

2026-09-15：479/479 Flutter 测试通过（新增 25 项），`dart analyze lib test` 无问题，`git diff --check` 通过。Windows debug 与 Android debug 构建成功，尚未安装真机。APK SHA256：`134834dba662f9dcb62abd1a71933a482cc0a42d4b5903b68acd8301423a83cf`。
