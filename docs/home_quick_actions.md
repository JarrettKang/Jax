# On-demand 首页快捷：实现与验收

日期：2026-09-05。代码和 Debug 构建完成；真实双端 rollout 等待 Android USB 调试授权。

## 产品与实现

1. 新字段：`Routine.showInHomeQuickActions` / SQLite `show_in_home_quick_actions`。
2. 新建与迁移均默认 false，不为用户已有 Routine 自动开启。
3. 只对 onDemand 生效：scheduled 已通过 recurrence 进入 Today，不重复固定。
4. Home eligibility：active + onDemand + true，展示时排除 running；沿用 Routine
   scoped order，最多 4 项，无独立快捷排序。
5. Scheduled 隐藏快捷开关；recurrence、TimeRule、Today 行为不变。
6. 无 unfinished 时沿用原 start，创建 RoutineExecution 和 open RoutineRunSegment，
   暂停已有 running，维持 global one-running。
7. paused 显示“恢复”，继续同一个 execution，不新建第二个 unfinished。
8. completed 后再次开始新 execution，支持同一天多次完成。
9. 每个按需 Routine 最多一个 unfinished 的既有事务约束不变。
10. inactive 保留 flag 并隐藏；reactivate 恢复显示。关闭 flag 不删除历史。
    切到 scheduled 清除 flag，切回 onDemand 默认 false；删除后入口自然消失。
11. 固定快捷动作不创建 Today obligation，未固定仍可从日常页执行。
12. Record 继续使用 RoutineExecution/RunSegment，没有第二套执行模型。
13. “添加执行记录”使用同一个 flag source，active + onDemand + true + not running；
    不受 Home 四项展示上限影响。
14. Recommendation Engine 源码未修改，TimeRule 仍只处理 Scheduled Candidate。
15. Home“快捷动作”与“接下来”独立；展示 Routine Category · 按需，不显示推荐理由。
16. 配置进入 snapshot/fingerprint/compare/apply/readiness，复用既有 3-way conflict，
    不使用 LWW；展示结果不入库、不同步。
17. schema 20→21 / protocol 7→8。DB CHECK 要求 0/1 且 scheduled 必须为 0；
    snapshot validator 与 readiness 同样检查。旧 baseline 读取时补 false，不写回源文件。

## 验收证据

Private device/data evidence omitted; engineering behavior is described separately.

## 备份与离线迁移

Private device rollout evidence omitted from this historical version.

