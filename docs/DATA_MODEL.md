# Jax 当前数据模型（Planning P4）

当前 SQLite schema version 为 `17`。时间字段均保存为 UTC Unix 毫秒，UI
显示时转换为设备本地时间。业务层级与执行事实严格分离：

`WorldNode → Plan → PlanItem → Event → RunSegment`

`Plan → PlanReviewNote`

Standalone Event 则不经过 Planning：`Event → EventDayPlan → RunSegment`。

## 长期结构与规划

- `categories`：World Category。仅 WorldNode root 或 standalone Event 可直接引用。
- `world_nodes`：长期关键节点；保留任意深度 parent/child、scope 内顺序与
  `inProgress/completed` 状态。child 不直接保存 Category，而是从 root 继承。
- `plans`：一个 WorldNode 的一轮规划。状态为 `focused/waiting/ended`；同一
  WorldNode 最多一个 current Plan，轮次号唯一。
- `plan_items`：Plan 内平级、有序步骤。状态为
  `draft/next/dispatched/done/dropped`。P3 仅允许 focused Plan 的 next item
  通过原子 dispatch 进入 dispatched；Event completion/restore 驱动
  `dispatched↔done`。
- `plan_review_notes`：Plan 下独立、可追加的复盘文本；保留创建/更新时间，
  focused、waiting、ended 均可新增、编辑和删除，不驱动任何规划或执行状态。

未产生执行事实的 Plan 可连同 draft/next PlanItem 物理删除，并正常产生 Sync
tombstone。若存在 dispatched/done PlanItem 或 linked Event，Data 层拒绝删除。

## Flat Event

`events` 是可计时、可进入 Today/Home/Record 的扁平执行对象，不再有
`parent_event_id`、child、breadcrumb 或 sibling hierarchy order。

| 字段 | 约束/含义 |
| --- | --- |
| `id` | TEXT 主键 |
| `name` | 非空执行事项名称 |
| `status` | `pending/running/paused/waiting/completed` |
| `source_plan_item_id` | nullable、UNIQUE、FK → `plan_items.id`、ON DELETE RESTRICT |
| `category_id` | nullable、FK → `categories.id`；只供 standalone Event 直接分类 |
| `first_started_at_utc` | nullable 第一次开始时间 |
| `completed_at_utc` | nullable 完成时间 |
| `created_at_utc` / `updated_at_utc` | Sync 元数据 |

CHECK 约束禁止 planned Event 同时保存 direct Category。来源类型由关系派生：

- `source_plan_item_id != null`：planned Event；Category 动态沿
  `PlanItem → Plan → WorldNode → root Category` 推导。
- `source_plan_item_id == null`：standalone Event；`category_id` 可直接引用
  World Category，也可为 null（未分类）。不会暗中创建 Plan/PlanItem/WorldNode。

UNIQUE + FK 保证一个 PlanItem 最多派发一个 Event，且 planned Event 必须指向
真实 PlanItem。P3 dispatch 在一个事务内创建 Event、建立关系、更新
PlanItem 状态并加入 current Today。跨设备并发产生的双 Event 会在 Sync
expected snapshot 校验中作为 `duplicate-event-plan-item` 拒绝。

## Today、执行与 Record

- `event_day_plans`：Event 与 JaxDay 的独立、有序关联；不修改 Event 本体。
- `run_segments`：Event 执行事实。Record、Daily/Weekly 与时间轴只从 segment
  读取；planned Event 的历史 Category 继续使用当前 WorldNode 动态归属。
- `routines`、`routine_executions`、`routine_run_segments`：独立重复行为体系。

Event 与 RoutineExecution 共用全局 one-running/open-segment invariant。开始或
恢复另一对象会原子暂停旧对象；waiting 不占 running、不累计时间；完成不自动
恢复旧对象。

## Sync generation

Schema v16 增加单例 `dataset_metadata.generation`。Schema v17 只新增空的
`plan_review_notes` 表及同步触发器。Sync protocol 5 的 snapshot、
fingerprint、compare、compile 与 apply 均携带 generation；不同 generation 明确
拒绝，避免 Development Data Reset 后旧 baseline/plan 复活旧业务世界。

Protocol 1–4 只在反序列化兼容层中升级；protocol 4 baseline 升级到 protocol 5
时不发明复盘记录。当前 snapshot 不输出 legacy Event hierarchy、Event sibling
list 或 LegacyEventWorldNodeLink。

Development Data Reset 清空所有业务实体、执行事实、tombstone 与绑定已删除实体
ID 的折叠偏好，同时写入双端相同的新 generation。外部 SyncStorageRoot、主题、
强调色和其它 device-local 设置不在这些业务表中，因此保留。
