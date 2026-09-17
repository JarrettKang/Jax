# PlanItem 提升为 WorldNode

## 只读审计与方案

WorldNode 通过 `parent_world_node_id` 自关联支持任意层级，只有根节点保存
category，子节点沿祖先继承。普通创建由 `PlanningController.createWorldNode`
与 `SqliteWorldNodeRepository.insertWorldNode` 完成，focus 可独立修改。
节点没有 note/description。Planning 始终是 WorldNode → Plan → PlanItem 单层。
首步已有原子、延迟创建 Plan 的入口，可直接复用。

原 PlanItem 只有 status，没有 type 或节点引用；title、note、sort_order 均存于
plan_items。draft 是历史存储兼容值，读取按 next 理解，新建只写 next。
Today 使用 current Plan / focused inProgress 节点下的未执行步骤；Home 仅消费
Event / Routine，不直接消费 PlanItem。Event 的 source_plan_item_id 建立执行来源。

采用用户请求的方案 B：保留既有状态 CHECK，添加 nullable
`promoted_world_node_id`；实体派生 `PlanItemType.worldNodeReference`。
这样不必重建被 Event 外键引用的 plan_items，也不改写历史执行事实。
非空引用优先于历史 status，属于不可执行、不可恢复的终止型结构语义。

## 行为

- 普通未执行步骤的 More → **提升为世界节点**，确认后留在父 Plan。
  只允许 current Plan、inProgress 父节点、next（含历史 draft）、无关联 Event。
  任意执行历史都通过 Event 归属，不能移动 dispatched/done 或已创建 Event 的步骤。
- SQLite 单事务中重新验证资格、创建 child、更新原步骤引用。失败全部回滚；
  条件更新与控制器忙碌保护防止重复创建。
- child.name = 原 title；parent = 原 Plan.worldNode；status = inProgress；
  focus 仅创建时继承父值，以后独立；category 按既有祖先规则继承；同级末尾追加。
- 不创建空 Plan、Event、EventDayPlan、RunSegment。首次进入 child 并添加步骤时，
  复用 canonical Planning workspace 的首步事务。
- 原步骤 id / title / note / sort_order / createdAt 保留，仅引用和 updatedAt 更新。
  note 留在原步骤并显示于引用行，不另建 WorldNode 文本字段。
- 引用显示 ↗ 图标，名称使用目标当前 name；无开始、恢复、删除单步或提升菜单。
  可点击进入目标的 Planning workspace；重命名无需维护两份名称。
  child 完成后引用仍在并显示“已完成”；父 Plan 结束不影响 child 生命周期。
- Today、未执行摘要使用 `isExecutable`，排除引用。Home 数据源保持 Event / Routine，
  提升不产生候选；child 后续新增普通 next 可按自己的 focus 自动投影到 Today。

## 删除与 Sync

选择删除策略 B：外键 `ON DELETE RESTRICT` 禁止删除仍被 PlanItem 引用的节点。
当前 World 没有物理删除 UI，本次不新增。现有“删除整个计划”显式删除原步骤和
对应 tombstone，但保留提升的 child；目标自身其他 Plan/子节点约束仍按原规则处理。
不自动级联删除 child，不生成 dangling reference。

schema 22 仅追加 nullable 外键列和非空唯一索引（一个 child 由一个原步骤提升），
CHECK 限制引用保留 next/draft 历史状态。不重建 Event 依赖链、不改写旧行时间，
迁移可重复打开。旧行列值为 null，schema 21 → 22 保留既有业务字段。

Sync protocol 9 使用 `promotedWorldNodeSyncId`，纳入 serialization、business
fingerprint、关系比较、手动冲突选择及 mutation apply。WorldNode 先创建再应用
PlanItem；删除 PlanItem 在删除 WorldNode 之前。validator / readiness 检查目标、
状态、执行关联，mutation 事务末再次检查并执行 foreign_key_check。
目标缺失、重复引用或引用同时带执行事实都会拒绝。

旧 protocol 8 baseline 仅给 live PlanItem 补 null 引用，并升级协议；元数据、
generation、历史字段、tombstone 保留。旧原始数据库必须先由新版 App 迁移到
schema 22 才能 Sync；Windows 与 Android 两端应同时升级。并发“提升/开始”或
“提升/另一提升”是显式冲突，不使用 LWW，也不把半套状态自动合并。

## 验证范围

新增数据测试覆盖字段继承、顺序与历史字段、focus 独立、lazy Plan、历史 draft、
非法状态/已有 Event、并发重复、事务回滚、重命名/移动/完成/父 Plan 结束、
受限删除、schema 21 迁移与重复打开。
真实 SQLite 双库测试覆盖双向 Sync、失败回滚、并发冲突、目标删除/tombstone、
旧 baseline 兼容。Android 390px 与 Windows 1200px widget 测试覆盖确认/取消、
引用位置、进入 workspace、首步创建、名称与完成状态、结束父 Plan 后导航。

本轮不安装真机、不对真实数据库执行 Sync Apply、不重建 baseline 或 generation。
不支持撤销提升、WorldNode 降级、已有执行步骤提升、单独删除引用；这些是第一版边界。

2026-09-14 验证：`flutter analyze` 无问题；完整 `flutter test` **355/355** 通过。
其中本功能新增 24 项测试（数据 15、双库 Sync 7、两端 widget 2）。
旧迁移测试明确断言新增列为 null，同时保持所有旧字段不变。
`flutter build windows --debug` 与 `flutter build apk --debug` 均成功。
产物为 `build/windows/x64/runner/Debug/jax.exe` 和
`build/app/outputs/flutter-apk/app-debug.apk`；Android Gradle 的 native-access 提示
为构建环境警告，不影响产物生成。平台交互结论来自自动化 widget 测试，尚未做本版真机验收。

## 用户授权真机安装（2026-09-14）

Private device rollout evidence omitted from this historical version.

