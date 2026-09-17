# 暂停并修改暂停时间

## 修改前审计

- Home 的 `_eventHero` / `_routineHero` 是 Android、Windows 共用的 running action menu。原“完成并修改结束时间…”调用 `_showCorrectedCompletion`，内用 Flutter `showDatePicker` / `showTimePicker`。这不是独立的全局 picker 组件，但两个对象共用此对话框。
- Event 路径：`EventController.completeAt` → `ExecutionSegmentService.validateCompletionEnd` → `CompleteEvent` → `EventRepository.pauseEvent`。Routine 路径：`completeRoutineAt` → 相同校验 → `RoutineService.complete` → `completeRoutineExecution`。
- `validateCompletionEnd` 复用 `_validateClosed` 和 `_validateOverlap`，遍历 Event / Routine 两类记录。结束必须严格晚于开始，不能晚于当前时间；首尾相接可接受，交叉区间拒绝。既有修正规则不允许零时长。
- 普通 Event 暂停通过 `PauseEvent` 读取 open segment，用 now 关闭，并把状态改为 paused。Routine 的 `_stop` 使用相同方式关闭自己的 segment。两者实体/表不同，但都是区间计时，SQLite 将状态与关闭执行段放在同一事务内。
- 之前没有统一的指定时刻关闭 API；修正完成的 overlap 在事务外，SQLite 关闭段时只验证 open，未完整验证 owner 状态、原开始时间及修订时间。

## 实现

- 新菜单项为 **暂停并修改暂停时间**，放在修改开始时间与修正完成相邻位置。标题为 **实际暂停时间**，提交按钮为 **暂停**。普通暂停、等待、完成保留。
- 对话框统一为 `_showCorrectedEnd`，暂停/完成只改变文案和提交回调。取消不调用服务；默认 now，手动 picker 按既有分钟精度选取，底层仍存 UTC 毫秒。提交期间防重复触发。
- `ExecutionSegmentService.closeRunningEventAt` / `closeRunningRoutineAt` 统一承接两种修正操作。两类对象按各自实体写入，时间与跨类型 overlap 共用原 `validateCompletionEnd`。目标状态通过 pause 参数确定。
- Controller 在打开对话框时捕获原 owner、updatedAt、open segment 的 id 和 startedAt。提交时重新读取核对，Routine 使用原 execution id，不重新选择当前 JaxDay occurrence。
- 仓储关闭方法可带 `expectedUpdatedAt`。启用修正模式后，SQLite 的 `_validateRunningCloseIn` 在写事务内再次验证时间范围、owner running/修订时间、唯一 open 段的 id/startedAt、全局 open 段以及跨 Event/Routine overlap。复用 `_validateNoSegmentOverlapIn`，按动作提供对应冲突文案。
- 验证后更新原 open segment.endedAt 与 owner 状态，失败整笔回滚。修正完成仍设置 completedAt、完成关联 PlanItem；修正暂停不完成关联步骤。普通暂停、普通完成和 waiting 流程没有改动。
- `_enqueueExecution` 串行执行，`_change` reload 并通知 Home / Today。没有 corrected-pause 展示状态。Record 和时长仍读取原段；恢复沿用现有 API，新建下一段。

## 数据与 Sync

没有 pausedAt、duration override、新实体或操作日志。仅使用已有 lifecycle 调试日志。schema 仍为 24，Sync protocol 仍为 11。

测试通过两个隔离 SQLite 数据库实际执行 snapshot → compare → compile → apply，覆盖 Windows→Android、Android→Windows 各自的 Event / Routine 状态、endedAt、65 分钟时长与 business fingerprint。

## 验证范围

- 新增 20 项测试：Planned / Standalone Event、Scheduled / OnDemand Routine，13:00–14:05=65 分钟，15:00 恢复新段，Record 时间源、关联 PlanItem 未误完成。
- Android / Windows widget 测试各覆盖 Event / Routine 的入口、取消、非法时间留在对话框、成功退出 Hero、Today 恢复操作。
- 相等/早于开始/未来时间、同类型/跨类型 overlap、状态或修订已变化、缺失 open 段、恢复后的新段拒绝过期回调、事务内冲突检查、注入 SQL 故障回滚。
- Routine 跨 23:00 后仍关闭原 occurrence；修正完成回归和双向 Sync 测试。
- 未使用真实用户事项做修改时间或同步实验；双端同步验证使用隔离数据库，UI 验证使用 Flutter 平台配置测试。此轮不自动安装真机。

## 边界

遵循既有规则，选择暂停时间等于 startedAt 会拒绝。错误提示沿用共享校验中的“结束时间”，表示当前执行段的结束。无法修正任意历史段；遇到过期状态需取消后重新操作。同步的乐观检查使用现有 updatedAt 与段身份，未新增独立修订字段。

## 最终结果

2026-09-15：448/448 Flutter 自动测试通过（新增 20 项），`dart analyze lib test` 无问题，`git diff --check` 通过。Windows debug 与 Android debug 构建成功。尚未安装到真机；未在真实用户数据库执行修正或 Sync Apply。
