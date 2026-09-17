# Today 移除操作清理

## 修改前审计

唯一生产 UI 入口在 `events_page.dart` 的 Event 行：除 running / completed 外都展示“移出今日”图标，因此 pending / paused / waiting 的 Planned 与 Standalone Event 均可调用。Home 没有该入口，也不调用 `removeFromToday`。Routine 与 projected PlanItem 从未提供这个操作，没有需要删除的 Routine 菜单。

`EventController.removeFromToday` 原来仅排除 running / completed，调用 `EventDayPlanRepository.removeEventDayPlan` 删除当前日归属。不会删除 Event，不改状态、PlanItem、执行段或历史。

EventDayPlan 仍负责 Event 今日归属、排序与前日未完成 Event 的一次性 carry-over。next PlanItem 是 Planning 动态投影，Routine 则来自 recurrence、Temporal lifecycle 和 execution；Routine 不使用 EventDayPlan。Home Work 按原 PlanItem/关联 Event 查询，waiting 单独按执行状态查询。

底层删除 API 被 DayPlan、Planning dispatch/withdraw、carry-over 与 Sync 相关测试使用，保留。用户动作的限制放在 Controller，低层存储 API 不改变语义，避免影响同步/修复。

## 最终行为

| 对象 | 今天先不处理 |
|---|---|
| pending Standalone Event | Today 行更多菜单内可用 |
| paused / waiting / running / completed Standalone Event | 无 |
| 任意状态 Planned Event | 无 |
| projected next PlanItem | 无 |
| Scheduled / OnDemand Routine，包括已有执行 | 无 |

生产 UI 不再使用“移出今日”文案。新菜单使用现有 `EventMoreMenuButton`，文案为“今天先不处理”，不占用主操作区。不新增 Home 入口。

`canDeferToday` 统一 UI 与 application 资格：isStandalone 且 pending。`removeFromToday` 名称保留，通过执行队列与其他 execution commands 串行，在提交前重新读取 Event、拒绝不存在或不合资格对象；UI 展示失败消息。

## 数据与刷新

删除的仍只是当前 JaxDay 的 EventDayPlan。Event、历史、其他日期归属、PlanItem 均保留。Controller 正常 reload 通知 Today 更新。

当前日已有 carry-over 初始化记录，刷新不会重新添加移除项。次日只从前一日仍存在的 DayPlan 结转未完成 Event，因此已移除事项不会自动回来；这是现有规则，没有新增 defer/snooze。现有显式加入今日能力仍可重新添加该 Standalone Event。

EventDayPlan 模型、仓储、数据库、Sync、Routine 生命周期、Planning、Home 主流程均无修改。schema 24 / protocol 11 保持不变。

## 验证

- Android / Windows widget 测试枚举 Planned/Standalone 的所有 Event 状态，验证菜单资格、取消旧文案、移除后即时隐藏、Event 保留和刷新不恢复；不合资格状态的 application command 也被拒绝。
- 两平台枚举 Scheduled / OnDemand Routine execution 状态，检查无移除菜单且执行事实保留。原 projected PlanItem 测试增加无移除操作断言。
- 原 Planned Event withdrawal 测试改为验证拒绝移除，同时保留“收回到计划”能力。
- 隔离 SQLite 测试覆盖前日结转→今天先不处理→当日刷新→次日无自动回归→显式加入，以及 Windows→Android / Android→Windows 的真实 snapshot/compare/compile/apply。同步后 membership 和 business fingerprint 一致，目标端刷新不回填。
- 此次不在真实用户数据上执行“今天先不处理”或 Sync Apply。

2026-09-15 验证：454/454 Flutter 测试通过（新增 6 项，覆盖状态矩阵），静态分析无问题，diff 格式检查通过。

Windows debug / Android debug 构建成功；此轮尚未安装真机。APK SHA256：`754b3f40bf50c2647d1ea2bea65fbb1d1b350e5789d6b11373ae80799cdb39e7`。
