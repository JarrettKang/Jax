# Planning Phase P3 contract

> **Status update:** This document preserves the P3 dispatch contract and its
> original scope boundary. The Review and World second-layer work deferred here
> was subsequently implemented in **Planning Phase P4**. Current status and model
> ownership are defined by `PRD.md`, `Development_plan.md`,
> `docs/planning_phase_p3_5.md`, and `docs/planning_phase_p4.md`.

Phase P3 建立唯一的 `PlanItem → Event → Today` 派发边界，不改变
SQLite schema v16、Sync protocol 4 或 dataset generation。

## Recommendation

P3.5 后，Today 只读展示 focused + inProgress WorldNode 的 current Plan 中的 next
PlanItem。建议不落库，不出现在
Home，不自动 dispatch。分组顺序为 Category order、WorldNode hierarchy/display
order、Plan round/id、PlanItem order/id。notFocused WorldNode、ended Plan 和非 next
item 不可见。

## Atomic batch dispatch

提交时用当前设备时间解析 23:00 JaxDay。Repository 在一个 transaction 中
对每个选中 item 重新校验：WorldNode focused + inProgress、Plan current、item
next、不存在 linked Event。然后
按 UI 可见顺序：

1. 创建 pending Event，拷贝 item title，设置 `source_plan_item_id`，不写 direct Category；
2. 以 guarded update 将 PlanItem `next → dispatched`；
3. 将 EventDayPlan 追加到 current JaxDay 末尾。

任意一项失败导致整批回滚。重复点击/过期 UI 不会产生第二个 Event。

## Lifecycle coupling

planned Event 首次进入 completed 时，linked item 必须为 dispatched，并在同一
transaction 进入 done。running Event 完成时，Event update、open segment close 与
item transition 三者原子。restore 要求 Event completed + item done，并原子转为
Event paused + item dispatched。状态不匹配拒绝并回滚。Standalone Event 不触发
Planning 状态。

## Removal, deletion, and sync

从 Today 移除只删除 day relation。未完成 Event 可从固定“已有事项”入口重加，
不再次 dispatch。planned Event 普通物理删除被拒绝，P3 不定义 withdraw。
WorldNode 取消关注或 Plan 转 ended 不修改已派发 Event、Today 关系或 Record 事实。

Readiness 与 snapshot validator 要求：executed item 有唯一 Event，unexecuted item
无 Event，done 必须对应 completed Event，dispatched 必须对应 non-completed
Event。两端对同一 item 独立 dispatch 得到两个 identity 时，Sync compiler 以不变式
冲突拒绝 expected snapshot，需后续人工解决，不执行真实 apply。

Review/Replan、withdraw 和 World second-layer visualization 均留到 P4 或之后。
