# Home 动态 World Category 入口

## 审计与实现

Category 已有 id、name、sortOrder、colorKey。根 WorldNode 的 categoryId 可空；子节点的有效分类通过祖先根节点取得，复用 PlanningController.categoryForNode。不能把子节点自己的 null categoryId 当作未分类。

Root 与 Temporal 主推荐下面使用同一个 homeCategoryEntries：从 focusedWorldNodePlanning 的 focused + inProgress 节点提取有效 Category id 并去重，不要求 Plan、PlanItem 或 Event。按 World 已加载的 Category 顺序显示；数据库排序为 sortOrder、created_at_utc、id。无有效 Category 的节点派生为末尾的“其他”，不创建分类数据。入口仅显示名称和已有颜色，无数量。

原 HomeIntent.root/work 枚举和固定“工作”按钮删除。原 HomeWorkItem/Group、homeWorkGroups、Work UI 泛化为 HomeCategoryItem/Group、homeCategoryGroups、Category UI，没有复制页面。HomeNavigationState 仅保存 categorySelected、可空 categoryId、推荐查看状态和各分类滚动位置，不持久化、不 Sync。

## 候选与动作

Category View 只保留有效 Category 匹配的 focused + inProgress WorldNode，沿用原节点排序。每组始终显示节点及“规划一下”，候选为空时显示“还没有可执行步骤”。

候选查询在已加载数据上完成：一次按 WorldNode 整理所有 Plan 条目，再按当前分类构造分组。current Plan 中可执行的 next 条目可开始；所有 Plan 中已有来源 Event 的未完成条目继续显示（包括 ended Plan、Today 外的 Event）。原查询仅扫描 current Plan 会漏掉 ended Plan 的未完成 Event，本轮补齐。promoted 条目不参与可执行候选。

按 sourcePlanItemId 构造 Event 索引；同一条目存在 Event 时仅展示 Event，完成则整行退出，否则仅在 current + next 时展示 PlanItem。沿用原执行服务、暂停/等待能力和事务；paused、waiting 可继续或完成。开始后 Running Hero 最高优先，结束执行后保留分类上下文。

## 导航、刷新与边界

“规划一下”仍 push 原 PlanDetailPage(worldNodeId)，不创建 Plan round；返回 reload，保留分类及滚动。Android Back / Windows Escape / 页面返回保持 Planning → Category → Root。主动查看 Temporal 推荐后，返回原分类。

每个分类拥有独立 ScrollController、PageStorageKey 和会话 offset。分类切换、Planning 返回以及主导航离开再返回时保留位置；内容缩短时允许框架限制到有效范围。

分类 rename/reorder 使用 Controller 最新对象；节点移类、取消最后一个 focus、完成最后节点或删除分类后，成功加载时重新验证入口。当前入口消失则回 Root；加载中或加载失败不错误丢弃上下文。删除分类后无有效分类节点自然进入“其他”。

Temporal selector、真实时间边界和 Running 优先级不变；已选择分类后到点仅轻提示，不抢页面。全局 Waiting 管理入口继续保留；来源 waiting Event 同时可在所属节点中操作，仍是同一数据对象。临时事项仍复用 Standalone 创建流程。

## 范围与验证

不修改 Today、Record、Planning 业务、Recommendation Engine、schema 24 或 Sync protocol 11。Home 不增加任何持久化分类或导航字段。

自动测试覆盖 Android 360/390 小屏、Windows 1200 宽屏，分类去重、祖先继承、无 Plan、其他、顺序/改名/移除、完成节点排除、无统计与固定入口、分类隔离、独立滚动、加载错误保护、删除安全返回；原 SQLite UI 测试继续验证实际规划返回、创建步骤、执行接管、暂停/等待、完成和导航不写业务表。数据库回归覆盖 ended Plan 的 pending/paused/waiting Event、完成退出和历史段不变。

2026-09-15：完整 Flutter 测试 483/483 通过，dart analyze lib test 无问题，git diff --check 通过；Windows debug 与 Android debug 构建成功。日志位于 .debug_backups/home_category_full.log、home_category_windows_build.log、home_category_android_build.log。已按下述流程覆盖安装真机；未通过操作真实执行事项测试功能。超多分类、字体极端放大及真实设备手势尚需后续体验；第一版按需求不折叠或分页。


Android debug APK SHA256：`5587ad6495c1c685ffd838be15192f4762468eb061455f10a8ff4168ea2dea51`。


## 真机安装记录

Private device rollout evidence omitted from this historical version.

