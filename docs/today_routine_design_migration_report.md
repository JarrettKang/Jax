# Today + Routine Design Migration Report

## 修改前只读审计

依据：docs/DESIGN.md v1.0、当前实际代码。业务状态、时间计算、资格查询与存储不属于本轮改造范围。

| 范围 | 当前事实 / 遗留视觉 | 迁移方向 |
|---|---|---|
| Today四区 | running置顶、active/overdue、persistent、later；空区隐藏；18间距、标题带数量 | 保留资格及顺序；sectionTitle17、24间距，移除无必要数量 |
| 普通Event/PlanItem/Routine | _TodayExecutionRow，700断点三列；标题2行、metadata1行截断；3px分类色running边、.10分类底/.55 hover | 纯视觉shell，完整换行、semantic running、稳定time/action槽 |
| paused Routine | PausedRoutineRow独立Column，12padding；occurrence日期；右对齐按钮 | 显式opt-in共用shell，保留execution身份与回调 |
| waiting Routine | WaitingRoutineRow另一Column，category+等待，8空隙 | 同上，waiting中性沙漏，不用warning |
| PlanItem | direct WorldNode来源；不重复未开始；start会转为关联Event且去重 | 来源、start、排序/去重全部保留 |
| Standalone Event | 无WorldNode时显示category/未分类；沿用Event row | 同一shell，无分类时轻量“临时事项” |
| Temporal | active与overdue文案已有，但无明确warning，Later时间埋在subtitle | overdue warning文字；Later独立时间槽；不改latest→ideal→start排序 |
| 时间与刷新 | lifecycle boundary timer、resumed load、JaxDay与occurrence query已有 | 不动timer/controller/core |
| Today动作 | shared button默认complete Filled、44/compact；状态切换排列不同；独立排序按钮与More | Phase C显式48、普通Secondary、running暂停Primary；原资格与回调保留 |
| Routine列表 | 按Category组织，Scheduled/On-demand用recurrence/type区分；不是两套业务列表 | 保留分类组织；统一title/meta/time/status/actions，无新增筛选分组 |
| Routine行 | 540断点；短标题/recurrence截断；76执行+96排序+48More固定槽挤压手机标题 | 共用视觉shell；排序移入More，调用原排序方法 |
| Routine category | 10顶部间距、默认Divider、title700；96排序+48More | section17、紧凑留白，分类管理收进More |
| Routine执行 | Scheduled从Today执行；Routine页On-demand可start/resume，paused More已有恢复/完成；running无本页暂停入口 | 保留现有页面分工与capability，不借视觉迁移新增工作流 |
| Routine edit | 420宽滚动dialog；名称/分类/类型/重复/三时间字段缺少分组 | 基本信息、重复规则、时间推荐；同组label/value；保留picker与保存验证 |
| 三时间 | 开始/理想/最晚顺序已有；仅HH:mm，缺次日说明 | 只在显示层补相对开始推荐的“次日”；不改底层unwrap |
| Quick Action | edit state持有showInHomeQuickActions并保存，但当前无toggle入口（Home另有管理） | 不新增设置；保存现有值行为不改 |
| correction | Routine页没有开始/暂停/完成时间修正入口；Home有相关入口 | 不新增、不修改Home |
| Delete | Routine是停用/重新启用；仅分类删除有确认 | 分类delete error；不把停用冒充永久删除 |
| 共享/平台 | shared buttons、paused/waiting被Home等调用；Today1080/Routine1000；统一20页边距 | 新选项默认保持旧行为；局部主题；Android16/Windows24；双端1×/2×/窄宽验证 |

已符合规范：连续列表无逐行Card、四行动分区、执行资格与时间资格分离、无未开始冗余、直接WorldNode来源、已有局部最大宽度。视觉重复集中在执行行布局；可共享slot shell与token，不共享包含各类业务查询/资格的万能row。

状态保护：completed/expired继续按现有规则退出Today；unfinished paused/waiting不因跨日或过期消失；waiting不计主动时长；paused可直接complete；On-demand不补虚构三时间；原排序/More/编辑保存路径不改业务实现。

## 实施结果（Phase C）

Today、Routine 均为 **migration implemented / awaiting real-device validation**。本轮没有真机安装或主观验收，不进入 Phase D。仅依据 canonical DESIGN.md，未重新查阅外部风格。

### 文件与 widget

| 文件 | 本轮作用 |
|---|---|
| `lib/ui/pages/events_page.dart` | Today 局部主题、四分区标题、各来源的视觉适配、时间与动作层级 |
| `lib/ui/pages/routine_page.dart` | 管理列表、分类与 Routine More、编辑分组、时间显示 |
| `lib/ui/theme/operational_theme.dart`（新增） | 复用既有 palette / typography / controls，仅在两页启用 |
| `lib/ui/widgets/execution_row_shell.dart`（新增） | 无业务实体依赖的 marker / title / metadata / status / time / action 槽位 |
| `lib/ui/widgets/paused_routine_row.dart` | 新增默认关闭的 `operationalVisuals` 选项，Today 显式启用 |
| `lib/ui/widgets/waiting_routine_row.dart` | 同上；保留 execution identity 与原回调 |
| `lib/ui/widgets/execution_action_buttons.dart` | 可选 label 覆盖，默认仍使用原 action label |
| `test/ui/today_routine_design_migration_test.dart`（新增） | 48 组双平台宽度/字号/状态布局矩阵与截图生成 |
| `test/ui/routine_page_test.dart`、`routine_reorder_test.dart`、`routine_category_page_test.dart` | 更新 More 排序入口、独立状态文字、无数量标题的 UI 断言；保留存储/排序断言 |
| `test/ui/paused_completion_test.dart`、`corrected_pause_test.dart`、`dynamic_today_test.dart` | Today 继续文案及状态/日期分离定位；保留执行与时长断言 |
| `test/ui/mobile_pages_test.dart` | 长标题完整换行后先滚动定位；新增按钮实际可点击检查 |
| `docs/DESIGN.md`、本报告 | 实施状态、局部变体、验收清单；依据用户确认更新 World Android 验收状态 |

### 视觉迁移决策

| 主题 | 最终实现 |
|---|---|
| Today section | 保留正在进行、现在需要处理、持续事项、稍后；空区隐藏。17 sectionTitle、24 区间距，去掉数量和逐行 divider，无 Card header |
| execution row | source-specific 适配器传纯视觉槽位；shell 不读取 controller、实体或资格，不承担开始/暂停等业务 |
| paused / waiting | 与普通 Event/Routine 共享标题、metadata、状态、time/action 排列；pause / hourglass + 中性文字；按钮顺序统一继续→完成，按原 capability 显示 |
| running | 继续置顶；accentSubtle、accent 2 侧线、16 marker，紧凑 timer；不用 Category 色、Hero 圆角、阴影。主动用时读取原 controller，未增加计时源 |
| active / overdue | active 显示理想完成前；overdue 仅 warning 时间说明，保留 latest→ideal→start 排序，不把等待状态染黄 |
| Later | HH:mm 独立 time slot，附开始推荐说明；窄屏在标题上方，宽屏稳定时间列，非 subtitle 中的一段文字 |
| persistent | 正常 title + 轻 metadata、Outlined 开始；PlanItem 仅显示直接 WorldNode；不显示计划步骤/下一步/未开始 |
| Standalone Event | 同一 shell，已有 Category 仍可作为来源；没有来源时使用临时事项，不强制新增分类 |
| Routine list | 保留按 Category 组织；Scheduled 显示 recurrence、三时间摘要；On-demand 显示按需和原开始/继续入口，未补时间字段 |
| Routine edit | 基本信息→重复规则→时间推荐；字段间 16、组间 24；滚动弹窗、名称完整换行、原错误反馈与保存路径 |
| 三时间 | 开始推荐→理想完成前→最晚完成前，label/value + 轻说明；同组小型 TextButton；保留原系统 picker，次日只属显示层 |
| execution state | 两页统一 running/paused/waiting/completed 的 icon + text；Today completed/expired 依原规则退出，未增历史区；Routine 管理态可显示既有 completed |
| button hierarchy | 48 最小目标、8 圆角；Today running 暂停为 Primary，其余普通执行操作为 Secondary；More 低强调但常驻可发现 |
| Category color | 仅保留 Routine 分类色点表达身份；不表达执行和 Temporal 状态 |
| sorting / More | Routine 及分类上下移移入 More；仍调用原排序方法，快速连续排序的确定性回归保留。Today 原有上下移资格与入口保留 |
| Quick Action / correction | 实际 Routine 编辑器没有 Quick Action 开关，保留原值及类型变化时的原行为；不新增开关。纠正时间入口保持原页面分工，未给管理页新增动作 |
| destructive | 分类删除为 error；沿用确认及记录保留说明；Routine 停用/重新启用保持原语义 |

### 使用的规范与场景变体

复用既有 HomePilot / PlanningTheme 中的 canonical 值：canvas `#F7F7F3`、surface `#FFFFFF`、surfaceSubtle `#EFEFE9`、textPrimary `#252A27`、textSecondary `#555E58`、textMuted `#68716B`、accent `#315C4C`、accentSubtle `#E7EFEA`、warning `#865C19`、hairlineStrong `#818B83`。pageTitle 26、sectionTitle 17、itemTitle 16、body 14、metadata 13；spacing 4/8/12/16/24/48；按钮 radius 8、触控目标 48；focus accent 2 描边、hover 轻表面。继承现有 error / input / control theme，不新造全局配色。

新增的局部 contextual variant 已写入 DESIGN.md §19：Today 1080 / Routine 1000 最大宽度；行内宽 ≥880 且 16 字号放大后 ≤20 才横排，marker 24、time 108、action 344，槽间 16。窄屏/大字号采用纵向时间、标题、动作区；动作 Wrap。紧凑列表 timer 采用 16 号等宽数字，区别于 Home 的 32 号 Hero timer；不改全局字体 token。

Android 横向页边距 16，Windows 24。Windows 鼠标 hover 不改变几何，宽窗口显示明确时间列；高 DPI/窄窗口回退可换行布局。Android 编辑内容随键盘 inset 缩小并可滚动，保存/取消留在弹窗操作区。320 宽、2 倍字号时三时间标签和“次日”允许折行，未裁掉时间值。

### 共享范围与业务保护

Home / Planning / World 页面与原 theme 文件逐文件 hash 保持本轮开始时状态。共享 paused/waiting 新选项默认 false，只有 Today opt-in；action label 覆盖是可选参数，默认不变。Record / Settings、App shell、Core、Data、Sync、controller 未修改。

未改 TemporalEngine、occurrence 归属、JaxDay 边界刷新、candidate ranking、去重、计时、主动时长、执行转移、存储或同步。Routine 管理页原本没有完整 running 暂停/等待/完成操作区，本轮没有增加该工作流；这些执行操作仍由 Today 等既有执行入口提供。暂停直接完成、等待不计时、跨日未结束执行可达性均沿用原实现并保留回归覆盖。

## 真机验收 Checklist（全部待用户体验）

1. Today 四个 section 是否自然，空区是否没有多余占位。
2. running 是否够明显，又没有压过整页。
3. 时间是否容易扫视，主动计时是否清楚。
4. active 与 overdue 是否容易区分。
5. overdue 的文字警告是否适度。
6. persistent 是否足够轻，来源是否清楚。
7. Later 是否一眼看懂何时开始推荐。
8. paused / waiting 是否仍像同一套行。
9. 开始、继续、完成与 More 的位置是否稳定、便于点击。
10. Today 是否仍像动态行动页，分区随现实执行与时间自然变化。
11. Routine Scheduled / On-demand 是否自然区分。
12. 三时间名称、顺序和同组关系是否清楚。
13. 推荐时间是否不会误解为执行 duration。
14. 跨午夜的“次日”是否容易理解。
15. 编辑页是否足够轻，分组是否帮助理解。
16. paused / waiting / completed 的状态语言是否一致，既有操作能否顺利完成。
17. More 中排序、编辑、停用与分类操作是否合理且易发现。
18. Android 默认/大字号、长名、键盘弹出、返回/取消是否舒服。
19. Windows 宽窄窗口、高 DPI、鼠标和 Tab/Enter/Escape 是否像同一个产品。

待验证限制：截图使用本机微软雅黑作为 QA 中文字体，不能代表 Android 字体与真实屏幕；自动键盘检查仅覆盖 Tab smoke，实际焦点顺序、输入法、Enter/Escape 手感需实机确认。大字号的行高与时间标签折行、More 收纳后的可发现性也需主观体验。无本轮用户验收结论，不标记 validated。

## 自动验证结果

2026-09-17：

| 检查 | 结果与证据 |
|---|---|
| `flutter analyze` | 无问题；`build/phase-c-analyze.log` |
| `flutter test` | **626 项全部通过**；`build/phase-c-full-tests-final.log` |
| 中文布局矩阵 | **48 组通过**：Android 320/390、Windows 480/1400 × 1×/2× 字号 × 6 场景；微软雅黑与 MaterialIcons 离屏截图在 `build/phase-c-qa/` |
| Android debug | 构建成功；`build/app/outputs/flutter-apk/app-debug.apk`；`build/phase-c-android-build.log` |
| Windows release | 构建成功；`build/windows/x64/runner/Release/jax.exe`；`build/phase-c-windows-build.log` |

全套测试包含 Today/Routine、Temporal 生命周期、暂停/等待/完成、纠正时间、跨 JaxDay、occurrence、主动时长、排序、投射去重、Quick Action、持久化与 Sync，以及 Home / Planning / World / app shell 回归。Core/Data 原有测试未修改。初轮旧 UI 定位失败已修正：常驻排序改为 More、恢复改为继续、状态日期拆开、窄屏先滚动再断言；业务断言保留。最终日志无测试失败或命中区域警告。

布局矩阵覆盖无 running、running Event/Routine、多个 active/overdue、persistent PlanItem、Standalone Event、paused/waiting Event/Routine、Later、长标题、跨午夜及管理页 running/paused/waiting/completed。编辑测试覆盖跨午夜三个字段、键盘 inset、取消、On-demand 无时间字段且保存保留 Quick Action 值；无时间推荐、recurrence 与空 section/时间边界由既有 Routine 与 dynamic Today 回归共同覆盖。

已人工检查代表截图：Android 390 普通运行态、320/2× Routine 运行态和三时间编辑、Later 与 paused/waiting、键盘 inset；Windows 1400 Today/Routine（含 running）。未发现裁掉关键动作或 RenderFlex 溢出。Windows hover 几何稳定、Tab smoke 通过，实际设备观感仍待验收。

示例截图（开发产物）：

- [Today Android running](../build/phase-c-qa/today-event-android-390-1.0.png)
- [Today Windows 四区](../build/phase-c-qa/today-mixed-windows-1400-1.0.png)
- [Later 时间槽](../build/phase-c-qa/today-mixed-android-390-1.0-later.png)
- [跨午夜大字号编辑](../build/phase-c-qa/routine-android-320-2.0-time-edit.png)
- [Routine Windows 运行态](../build/phase-c-qa/routine-running-windows-1400-1.0.png)

工作区原有改动保留，本轮未提交 Git。以开始时文件 hash 清单复核，本轮生产代码变化仅为上表七个 UI 文件；业务层、其他页面和原主题保持不变。双端构建未启动生产应用或修改真机数据。

## Android 覆盖安装记录

Private device rollout evidence omitted from this historical version.

