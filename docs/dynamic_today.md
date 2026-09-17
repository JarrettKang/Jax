# 动态 Today Phase 2

## 只读审计与范围

原 Today 来源为 EventDayPlan → Event、PlanningController.projectedTodayItems 和
EventController.todayRoutines。PlanItem 投影资格与顺序由 PlanningController 统一负责，
已排除 reference/promoted；EventDayPlan 顺序可用上下按钮调整。此前 running Event 仅在
Today 关系中出现，completed Event/Routine 仍显示，行按“今日事项 / 今日日常”分组。
Routine 行原来根据 routineId 选择当前可操作 execution；Phase 1 已读取 previous/current
两日记录，提供 temporalOccurrencesFor / executionForOccurrence，但缺少 Today 边界定时器。
App/控制器已有 resume 与 JaxDay 刷新，running 计时仍使用原 ticker。

本次新增 TodayTemporalView 纯计算展示模型，复用 Phase 1 resolved window，不修改其
时间语义，不增加表、schema、协议或业务实体。保留原 Entity、DayPlan、RunSegment 与 Sync。

## 分区与资格

空分区不显示标题；全空时显示“当前没有待处理事项”。顶部保留已有事项、临时事项入口。

- **正在进行**：running Event 始终置顶，即使当前 EventDayPlan 尚未加载/不存在。
  running Routine 同样保留操作入口，包括已越过 temporal latest 的执行，避免进行中的
  计时失去暂停/完成入口。复用轻量行，不复制 Home Hero。
- **现在需要处理**：recurrence 按原 occurrence day 命中、Routine active、启用时间配置、
  lifecycle active/overdue、尚未 completed/running。active 显示理想完成前；overdue 显示
  已超过理想时间与最晚时间。正在执行的单独置顶，已过期未执行项不显示。
- **持续事项**：原 Today 中未完成的 pending/paused/waiting Event，以及既有
  focused inProgress WorldNode / current Plan / 普通 next PlanItem 投影。
  无时间配置的 Scheduled Routine 仍保留，未完成且未 running 时在此显示。
  On-demand 原本不在 Today 主列表中，此次不新增按需候选；其已运行 execution 保持可操作。
- **稍后**：原 owner day recurrence 命中、inactive、未 completed，且 start 在当前
  JaxDay 结束前。显示推荐开始时间。如果同一 Routine 已有 active/overdue 或 running
  occurrence，抑制它的下一条同名稍后项；原 occurrence 完成/过期后恢复正常判断。

completed Event/Routine 退出行动列表但不删除实体、DayPlan 或 segment；Record 保留原历史。
paused/waiting Event 继续复用原恢复/完成能力。无“未开始”文字和重复状态圆点。
所有可开始项使用既有 ExecutionActionButton，包括 projected PlanItem。

## 稳定排序、身份和执行

现在需要处理按 resolved latest → ideal → start 升序，最后以 Routine order 与
occurrence identity 稳定兜底。稍后按 resolved start 排序。
PlanItem 复用 Planning 的 World hierarchy/order → PlanItem order；未开始步骤不随时间消失。
Event 复用原 DayPlan 顺序，保留持续 Event 之间的上下移动；running 分区不提供排序，
Temporal/PlanItem 无跨区排序，不新增混排 order 数据。

PlanItem 与来源 Event 使用同一逻辑 identity `plan-<sourcePlanItemId>`。
仅当 Event 真正可渲染时才隐藏 projection，兼容 Events 先于 DayPlan 返回的中间状态。
启动事务仍由原 startPlanItem 执行；Event load 完成后才发布 Planning load，避免空档。
启动后行被提到正在进行，这是显式优先级移动；暂停后可回到原会话的持续相对位置。
PlanItem secondary 显示直接所属 WorldNode，来源 Event 也优先显示该节点。

Temporal row identity 为 routineId@occurrenceKey。按钮携带实际 occurrence key，避免
在上一 occurrence 完成后，提前开始下一稍后项时再次定位到上一条。RoutineService 仅增加
显式 owner key 参数，校验它仍属于可用 previous/current 窗口；过期/失效点击给出错误提示。
执行始终写原 RoutineExecution/RunSegment，时间戳是真实时间，不转换为 Event。
全局 running 查询始终覆盖按时间选中的 execution，保证提前执行下一 occurrence 也可见。

## 响应与边界

页面监听 Event/Planning 控制器，focus、Plan ended、drop/start、execution complete/restore
及 recurrence 修改随现有 load/notify 更新。首次构建按当前时间解析，app resume 重载两控制器。
页面只有一个下一边界 Timer：start、ideal+1ms、latest+1ms 和 JaxDay end 取最近未来值。
加 1ms 遵循 Phase 1 对 ideal/latest 精确端点包含的定义；同一边界不会因执行 ticker 重复重建定时器。
到点只重算展示，不写 lifecycle/section/order；JaxDay 数据加载复用原控制器机制。
Timer 在 dispose 取消，controller 更换时重新绑定。无新增高频 polling。

## 验证与第一版边界

纯展示测试覆盖四阶段分区、completed/recurrence、latest/ideal/start 排序、active 与 overdue
共同排序、later start 排序、23:00/午夜 original occurrence 与下一条抑制、精确下个边界。
Android 360px / Windows 1200px widget 测试通过真实 Timer 推进 start/ideal/latest，检查
空标题隐藏、简化文案和无执行写入。跨日 widget 测试检查上一条完成后下一条提前开始的
不同 occurrence key，resume 测试检查恢复前台后的 overdue。原延迟 DayPlan 的 20 帧
测试继续确认 PlanItem→Event 只有一条记录，现在按产品规则提升到 running 分区。

本轮不修改 Home Recommendation Engine、持久化 schema/Sync、PlanItem 时间模型、
carry-over、Standalone 创建或 Record 页面。未实现跨区拖拽、动态路线预测、missed Review。
无时间配置的 Scheduled Routine 暂列持续事项；稍后沿用可提前开始能力，并绑定那一条
occurrence。已过期但 running 的执行保留在顶部，直至用户暂停/完成；过期后暂停则退出行动列表。

最终验证：完整 Flutter 测试 403/403 通过，`dart analyze lib test` 无问题，
`git diff --check` 通过；Windows debug 与 Android debug APK 均构建成功。
本轮仅完成自动化布局验收与构建，未安装真机、未执行手动真机验收。
APK SHA256：`0D926B23DC754B6F0305CC9FF6AF90F67CD0FB170BC4F990A12B96399D7CCBB1`。
