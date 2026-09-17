# Home：情境与下一步行动

## 只读审计和改动范围

旧 Home 同时展示 Running Hero、展开的 Event/Routine Waiting、最多三条 Recommendation、On-demand Quick Actions。HomeCandidateProvider 通过 Today Event 与 Scheduled Routine 生成候选，TimeRecommendationRule 将 active/overdue 时间事项提升，但其整体排序及 paused 资格不等于本轮“唯一且尚未执行的主时间推荐”。旧 Home 未直接展示全部 focused/current/next PlanItem；暂停/等待的 Planned Event 也没有按当前规划链归组。

PlanningController 已提供 focusedWorldNodePlanning、currentPlan、items、linkedEventFor 和 startPlanItem；Today 用 sourcePlanItemId 接管投影并以 plan-<id> 表达身份。PlanDetailPage(worldNodeId: ...) 是统一 workspace，可展示尚无 Plan 的节点，浏览不创建新一轮。旧 app 按选中主导航挂载单页，因此仅依赖 Home widget state 无法跨 tab 保留意图。

最小实现：新增 HomeNavigationState 会话 UI 状态及纯查询 homePrimaryRecommendation/homeWorkGroups；Home 接入现有 PlanningController。app 持有导航状态，Home 持有滚动控制器并把位置保存在会话对象。Today 仅把原临时事项编辑器提取成共用函数；EventController 增加复用 create/start/ensureToday 的临时事项立即开始入口。无数据库、Sync、Recommendation Engine 或时间语义变更。

## 显示优先级

1. Running Event/Routine：唯一主区域，继续使用原 Hero 和暂停/更多操作（等待、完成、修正时间等）。不显示顶层询问、工作列表或成组推荐。新 temporal 到点只出现轻提示，不自动暂停/切换。
2. 已选择 Work：保持 Work，即便候选变空或时间推荐变化；顶部显示可查看的时间提示和等待计数。
3. Root：若有未产生 execution 的 active/overdue temporal，显示唯一主推荐；否则显示“接下来想做什么？”。工作、临时做一件事始终可自由选择。

Work 提示的“查看”显式打开主推荐内容，“返回工作”回到原上下文。开始任何候选后 Running 覆盖当前内容；执行停止后，原来选过 Work 则回到 Work，否则重算 Root/推荐。Root Ask 不使用弹窗，不自动创建休息/空闲记录。

## Work 资格、分组与去重

按 Planning 既有稳定顺序列出所有 inProgress + focused WorldNode；每组使用 current Plan，步骤按 sortOrder / ID 排序。不展示完整 World tree 或 Plan round。

- 普通 next PlanItem（含兼容读取为 next 的旧值）直接提供开始；promoted WorldNode reference 不作为执行步骤。
- 具有 sourcePlanItemId 的未完成 Planned Event 取代对应步骤，pending 可以开始，paused/waiting 显示真实状态与继续。无需 EventDayPlan 命中今天。
- 优先用 EventController 当前执行/历史结果覆盖 Planning 缓存，再依据来源关系回退，避免异步刷新时重复投影或重新出现已完成事项。
- next → Event 的执行仍由 PlanningController.startPlanItem 和已有事务负责。相同来源始终只有 plan-<sourceId> 一条工作身份；Running 就绪后切换主区域。
- 没有 current Plan 或没有可执行步骤的 focused 节点仍显示名称、“还没有可执行步骤”和规划一下。整体无节点时显示空状态并保留返回入口。
- unfocus、ended、drop/promote、完成随控制器通知刷新，不把用户送回 Root。

## Planning 与会话导航

每组“规划一下”通过 Navigator.push 直接打开 PlanDetailPage(worldNodeId)，没有 Planning Overview 中转，没有 Home 专用编辑器，不自动创建新 Plan。返回重载 Planning / Event 查询，仍留在 Work。

HomeNavigationState 由 app 会话持有，保存 root/work、显式查看推荐以及 Work 滚动位置。切换主导航再回 Home 可恢复；app 完全重启重新计算 Root。无持久化 HomeSession、意图字段或 Sync 数据。

Android 返回：Work → Root，Planning → Work。Windows 提供可点击返回和 Esc；规划路由使用独立 FocusScope，输入编辑的键盘处理保持现有行为，结束输入后 Esc 可返回。工作列表保留原滚动控制器/会话位置；内容被删除导致列表变短时按 Flutter 正常范围收敛。

## Temporal、Waiting、临时事项

主 temporal selector 复用 TodayTemporalView 的 previous/current resolved occurrence、latest → ideal → start 稳定排序，只选 execution == null。running/paused/waiting/completed 均不再次作为“建议开始”。同 Routine waiting 的重复时间候选沿用现有抑制规则；23:00 后启动仍携带原 occurrence key。

Home 只有一个下一边界 Timer，复用 Phase 2 的 start/ideal+1ms/latest+1ms/JaxDay end 计算，再与问候语下次边界取最近值。移除旧 Home 每分钟重刷安排；执行计时沿用现有 running ticker。页面销毁取消计时器；resume 由 app 统一重载，Home 只重算展示并重新安排边界，避免重复初始化当天。

Waiting 默认为计数与查看入口，Work 中放在列表前。查看打开轻量管理页，Event/Routine 均可继续和完成；返回保留先前 Home 意图。等待不占 running slot，恢复冲突沿用原执行规则。

“临时做一件事”复用 Today 的 Standalone 名称/分类编辑器，提交按钮为开始。打开或取消不写数据；提交后调用已有创建、开始、加入 Today 流程，不创建 WorldNode/Plan。执行失败时沿用现有错误反馈；已创建的临时事项仍可在原执行数据中处理。

旧 Home Quick Actions 不再在根页面展开，On-demand 仍可从日常页执行/恢复；旧配置及业务数据没有删除；编辑器暂不显示已不适用的“首页快捷”开关，编辑原 Routine 时保留已有配置值。本轮不新增新的生活/娱乐意图。

## 验证和边界

新增测试覆盖 Root 无写入、唯一推荐排序与 execution 排除、跨日归属、Work 到点只提示、Running 不被覆盖、临时事项提交、Waiting 管理、两平台返回、Planning 修改后返回、真实 SQLite 逐帧接管去重、暂停/等待继续、focus/ended/drop 刷新、空 focused 节点、提升引用排除、非 Today 的遗留 Planned Event、主导航切换及滚动恢复。

第一版不做跨重启意图持久化、多个意图分类、工作排名或完整 Today 展示。等待管理是独立浏览页，完成/继续后可用返回回到原 Home 上下文。规划输入框仍遵守自身编辑快捷键；未提交的文本不由 Home 另行保存。

## 最终验收（2026-09-15）

完整 Flutter 测试 428/428 通过，本轮新增 11 项；Dart 静态检查无问题，git diff --check 通过。Android 小屏与 Windows 宽屏的自动化导航/布局/执行测试通过，Windows debug 和 Android debug APK 构建成功。未安装真机，未修改真实数据库或同步基线。

APK SHA256：D08484794FFADDA8126DD8310876F6970D5EF801D60075E3339C84AC517B98E1



## 后续演进：动态 Category

固定 Work 意图已泛化为 World Category 上下文，本文保留上一轮实现背景。当前行为以 docs/home_categories.md 和实际 Home 代码为准。
