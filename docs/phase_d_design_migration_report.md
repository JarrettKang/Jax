# Phase D — Record / Settings / Windows Migration Report

## 修改前只读审计

依据 canonical `docs/DESIGN.md`，不参考外部风格。以下为实际代码，不假定提示词中的建议功能已经存在。

| 范围 | 现状 | 本轮方向与保护边界 |
|---|---|---|
| Record页面 | SummaryPage，日/周切换→日期→总时长→分类汇总→24小时图→片段；无内容maxWidth，底padding96 | Operational上限1080；真实片段提前，图表仍可达，日/周查询原样 |
| 日/周 | injected clock / JaxDay anchor；周视图只有汇总，无周片段查询 | 保持切换、日期导航和聚合，不新增周事实查询 |
| Segment | 固定118时间列，title/body默认；仅时刻，无duration；isOpen显示正在执行；全部可点编辑 | 窄屏纵排、宽屏时间列；显示真实起止及主动片段duration；不把ended解释为completed |
| source | DailyExecutionSegment已有name/detail/category；无需新增模型 | 使用已有detail/category完整换行；实际service只返回分类/日常描述，无WorldNode路径，不能虚构已有数据 |
| 跨日 | 主summary范围有日期；segment与tooltip仅HH:mm | 起止跨日或不在所选自然日时补日期，保留真实未裁剪端点 |
| paused/waiting | service返回实际segments，图表DailyTimelineLayout按片段绘制 | 不合并间隙、不更改聚合、duration、completion、模型/存储 |
| 图表 | CategoryBar、WeeklyBars、DailyTimeDistribution；分类色正确；周150高、小时28/34；局部alpha、3radius、默认灰线 | 保留数据与交互；统一文字/线条/表面，缩放时适配；事实列表先于高图表 |
| 图表交互 | fragment命中宽最低32、高28/34；精细图形不可能全按48放大而不重叠 | 保留比例与已有入口，同时事实列表提供完整48可点击替代；记录contextual exception |
| Record编辑 | 4处bottom sheets，关闭片段改时/删除、open只读、补记对象与时间；既有picker/验证/保存 | Android保留sheet交互；Windows使用统一宽度居中modal；不改验证、边界和按钮操作 |
| Settings | 仅assistantName，无未来空组；上限820；ListTile value两行ellipsis；16页边距 | 局部规范主题、label/value/chevron完整换行，Windows24页边距 |
| 名称编辑 | 360dialog、人格问句、无input label；即时验证、保存中、取消、Enter保存、Esc受PopScope保护 | 中性标题与label，error就近；保留maxLength/validation/persistence及saving保护 |
| 已迁移宽度 | Home820、Planning820、World1040、Today1080、Routine1000 | 保持各页场景宽度，不统一拉成一个值；Record1080/Settings820 |
| 行密度 | Home/Planning原密度；三页compact已实施 | Windows polish不重做Today/Routine行，不改变Android已迁移页面 |
| hover/focus | Home按钮、Planning/World row已有；Record/Settings默认InkWell/ListTile；App壳默认Material theme | 新页采用accent2焦点与surfaceSubtle hover；Windows壳显式token，反馈不改几何 |
| 键盘 | Material按钮/菜单原有Tab/激活；Settings有Esc与Enter；无统一自定义快捷键 | 保持语义，通过测试检查Tab/Enter/Escape，不新建跨页快捷键 |
| scrollbar | Flutter桌面默认自动scrollbar，但非持续可发现 | Windows滚动行为统一可见竖向thumb；保持各scrollable controller，不扩散Android |
| dialog | 360/440/480/520等局部内容宽；尚无canonical三档宽 | 新增Windows-only确认/标准/复杂三档约束，Android原宽度保留 |
| narrow/wide | App壳600断点；窄窗底导航；已迁移行有缩放回退 | 维持导航；检查Windows resize和大字，Record不横滚核心信息 |

已符合：无普通记录Card，分类色表达图表身份，RunSegment事实模型、23点JaxDay、暂停/等待间隙与open segment来源正确；Settings无未来空组；已迁移页面有合理宽度。共享问题集中于Windows scrollbar、dialog约束和壳级反馈，不需重新修改业务row。

## 实施结果

### 1. 修改文件与边界

- `lib/ui/pages/summary_page.dart`：Record 布局、事实行、表单容器、分类/周图标签。
- `lib/ui/widgets/daily_time_distribution.dart`：原比例布局保留，token、缩放标签、跨日 tooltip 与焦点反馈。
- 新增 `lib/ui/widgets/record_time_labels.dart`：本地 HH:mm / 跨日日期 / duration 的显示格式。
- `lib/ui/pages/settings_page.dart`：设置行、中性表单、输入 label、完整 value、Windows Escape 取消。
- 新增 `lib/ui/theme/desktop_polish.dart`；`lib/app.dart`：Windows theme、三档 dialog、轻量 scrollbar；Android theme 原样返回。
- `home_page.dart`、`planning_page.dart`、`world_page.dart`、`events_page.dart`、`routine_page.dart`、`history_detail_dialog.dart`、`category_edit_dialog.dart`、`standalone_event_dialog.dart`：仅应用 Windows dialog 约束与相应 live builder context；不改变原有页面分区、行或回调。
- 新增 `test/ui/phase_d_design_migration_test.dart`；更新 `assistant_name_test.dart`、`responsive_shell_test.dart`、`summary_page_test.dart` 的标题与滚动到可见项断言。
- `docs/DESIGN.md` 与本报告：参数、例外、状态及人工清单。

与 Phase D 开始时的文件 SHA256 清单对比：Core、Data、Sync、所有 controller、数据库模型、保存/校验服务均未修改。工作区已有更改保留，未提交 Git。

### 2–6. Record：事实优先、时间与图表

日视图为：记录标题 → 日/周与日期 → 已记录时间 → 执行片段 → 分类汇总 → 24 小时图。原有日/周切换、前后导航、时钟注入及 23 点 JaxDay 边界不变。真实列表无需先滚过整张时间图；周视图维持原有 summary/category/day bars，不伪造周片段能力。

普通片段不加 Card、不加装饰时间轴。每行至少 48 高，上下 8；标题 16，来源与主动时长 13，内容间 4。时间 body 14 使用等宽数字。窄屏时间在标题上方，长名与 metadata 完整换行。内宽至少 720 且文字放大不超过 1.25 倍时采用 224 时间列、16 间距，其余交给标题与 metadata；列表 maxWidth 1080，避免大屏把事实拉散。

时间使用真实 start/end，不剪掉跨日端点。跨自然日或 start 不在所选自然日时补 YYYY-MM-dd；open 以“现在”为终点，并显示“正在执行”。显示 duration 仅计算这一条 segment 的主动间隔；原聚合、去重与数据库计时不变。关闭片段不标“已完成”，不会把暂停/等待前后的两条 segment 合为连续执行。

保留已有 Event/Routine `detail` / category 文本，日常已有“日常”来源标识。**真实数据限制**：目前服务没有提供 WorldNode 路径；本轮未扩展 controller/service 查询，因此不能宣称新增了长 WorldNode 路径展示。现有 source 文字全部可换行；长 WorldNode 关联的事项仍显示其实际事项名和已有分类。相关来源扩展不属于本轮视觉迁移。

分类色仅表达分类身份，图表无强阴影、无新增 Card。分类标签可换行，条形轨道 surfaceSubtle；24 小时图仍按实际分钟比例分段，小时与周标签随文字缩放增加空间；hover/focus 和 tooltip 不改变几何。图表只是摘要，精细命中区域有下述例外，事实行是完整操作替代。

关闭片段修改/删除、open 只读、补记候选、可用时间区间及 picker 继续调用原逻辑。Android 保留 bottom sheet，Windows 改为居中 complex modal；编辑和 open 内容可滚动，限制为窗口高度的 84%。删除沿用原操作，仅使用 error 文字色。

### 7–8. Settings：配置值与编辑

仅保留实际已有“管家的名字”，没有主题/同步/通知等空组。阅读宽度 820，label / value / chevron，value 不再两行截断。行不 Card 化；Windows 横边距 24，Android 16。

弹窗标题“管家的名字”，输入 label“名称”，带当前值、原 24 字上限与原校验。错误紧邻输入；取消是 text action，保存是 primary，保存中保留禁用与关闭保护。原 persistence、onSubmitted、error 与保存处理不变。Windows Escape 映射到同一取消路径，仅非保存中可以关闭；这是补齐原 barrierDismissible=false 弹窗的桌面取消入口。Android 行为不变。

### 9–15. Windows 全局 polish

| 页面 | 上限 | 密度策略 |
|---|---:|---|
| Home | 820 | 舒展，保持 Pilot |
| Planning | 820 | 思考工作区，保持现有密度 |
| World | 1040 | 结构树，保留 compact |
| Today | 1080 | 行动列表，保留 compact |
| Routine | 1000 | 管理列表，保留 compact |
| Record | 1080 | 事实列表，响应式时间列 |
| Settings | 820 | 简单桌面配置行 |

hover 复用 surfaceSubtle；键盘 focus 复用 accent 2 outline；普通 hover 不改变行高，不隐藏主操作。分类按钮、More、输入和原页面继续沿用已迁移控件。没有把 Home/Planning 压成 World 密度，也没有重做 Today/Routine。

Windows 自有 dialog 三档外宽：确认 400、标准表单 560、复杂表单 720；最大不超过 viewport − 80。Record 居中 modal 归复杂档；Routine 多字段编辑与节点选择归复杂档；名称/分类/时间修正归标准；删除/结束/提升确认归确认档。历史内容内部 width 在 Android 保留，Windows 外约束统一。Material 日期/时间 picker 保留平台适配，不强套业务表单宽度。

Windows 竖向滚动区显示可发现 thumb：6 宽、4 圆角，hairlineStrong，hover/drag 改 textSecondary。使用各 Scrollable 的原 controller；横向行为不改。窄窗沿用 app 600 导航断点，Record 高字号自动纵排；窗口放大/缩小重新布局。无新增核心横向滚动。

Windows 壳采用现有 palette 和控件样式，基础 textTheme 保留字体/权重继承，各已迁移页面仍由自己的 semantic theme 定义字号。Android `buildJaxTheme` 直接返回原值，额外 dialog constraints 为 null，scroll behavior 沿用原实现。

### 16–18. Tokens、例外及其他页面影响

复用 canvas / surface / surfaceSubtle / accent / textPrimary / textSecondary / textMuted / hairline / hairlineStrong / error；pageTitle 26、sectionTitle 17、itemTitle 16、body 14、metadata 13；spacing 4/8/12/16/24/48；按钮 radius 8、small radius 4、focus outline 2、普通行 elevation 0、目标 48。分类色仍来自原 palette，不引入品牌色或外部参考。

新 contextual variants 已写入 DESIGN：Record 1080/224/720 槽位、桌面 400/560/720 modal、6 宽 scrollbar。**比例图例外**：短片段命中沿用最低 32 宽和原 28/34 行高（放大字体时增长），不为达到 48 破坏图形比例/重叠关系；事实列表提供至少 48 高的可点击等价入口。此规则只用于精细图形。

其他页面仅 Windows 浮层与壳级样式受影响，Android 已迁移页面结构和密度保持。关闭中的 dialog 使用自己的 builder context，避免路由消失后读取失效 ancestor。无 business state / navigation flow / Sync 写入调整。

## 自动验证与构建

- `flutter analyze`：No issues found。
- `flutter test --reporter expanded`：**689 / 689 通过**，包括原有 656 项与新增 33 项，无跳过。
- Phase D 中文离屏矩阵与键盘专项：**33 / 33 通过**；检查了 Android 大字号 open sheet、输入错误、chart，Windows 宽屏事实列表/长名称、窄窗大字号编辑 modal；未发现 overflow。
- SHA256 范围检查：90 个 Core / Data / controller 文件与本轮起点一致。
- `flutter build apk --debug`：成功，`build/app/outputs/flutter-apk/app-debug.apk`。
- `flutter build windows --release`：成功，`build/windows/x64/runner/Release/jax.exe`（运行需同目录完整依赖）。
- 构建日志：`build/phase-d-android-build.log`、`build/phase-d-windows-build.log`。Android 构建出现现有 Java native-access 与 SDK XML 工具版本提示，未阻断构建；本轮不改工具链。
- 本轮未覆盖安装设备，未运行真实用户库的修改/迁移操作。

日志：`build/phase-d-analyze-final.log`、`build/phase-d-tests-final.log`、`build/phase-d-visual-final.log`；截图 `build/phase-d-qa/`；范围核对 `build/phase-d-scope.json`（这些是本机生成物）。中文离屏字体为本机 Microsoft YaHei 字体文件，仅用于 QA；不替代 Android 系统字体或真实显示器验证。

覆盖映射：

- 新增矩阵：Android 320/390、Windows 480/1400，1×/2× 文字，共 32 个 Record/Settings 场景；empty、single、multiple、open、cross-day、long title、day/week、chart、default/custom/long name、错误/保存/取消。
- 多片段数据含 10:00–10:30、11:00–11:20、11:40–now，确保间隙未连成执行；pause/wait 与 aggregation 的真实业务语义由既有 Core/Data 回归共同验证。
- Windows 专项：Tab 可到达名称行、Enter 打开、原输入提交动作保存、Escape 取消而不保存；三档 modal 外宽；矩阵 hover 不改变几何、竖向 thumb、宽窄 resize。
- 全量既有回归覆盖 Home wide/narrow、Planning 交互与焦点、World 深树、Today 多态、Routine 编辑、Record 补记/编辑与 summary、preferences 持久化以及 Android 导航壳。
- 长 WorldNode 路径没有当前 Record 数据入口，不伪造 fixture 来声称支持；保留在人工关联事项验收说明中。

## Phase D Manual Validation Checklist

以下均等待用户人工确认，自动检查通过不等于主观验收完成。

### Record

- [ ] 1. 执行片段是否容易读，进入页面后是否容易找到事实列表。
- [ ] 2. 起止、主动时长、open“现在”与跨日日期是否清楚。
- [ ] 3. 暂停/等待空档是否正确，片段结束是否未被误读为事项完成。
- [ ] 4. 分类与时间图是否不过度抢位，点选短片段及从事实行编辑是否自然。
- [ ] 5. 长标题/长分类自然换行；关联长 WorldNode 的事项显示其实际事项名与现有分类（当前无路径字段）。
- [ ] 6. Windows 大屏是否不会拉太散；Android 小屏、大字、底导航与滚动是否自然。

### Settings

- [ ] 7. 页面是否中性、稳定，没有聊天口吻。
- [ ] 8. 默认、自定义及长名称设置是否自然，保存与取消结果是否正确。
- [ ] 9. input / error / 保存中状态是否清楚；软键盘弹出后操作是否可达。
- [ ] 10. 是否只有已有设置，没有空洞未来功能。

### Windows

- [ ] 11. 各页 hover 是否自然，是否不移动布局。
- [ ] 12. focus 是否清楚，与 World focused/selected/hover 区分。
- [ ] 13. Tab 是否按阅读和操作顺序移动，More/category/input 是否可达。
- [ ] 14. Enter 激活/提交、Escape 取消/返回是否正常，保存中保护是否保留。
- [ ] 15. Home/Planning 留白与 World/Today/Routine/Record 密度是否各自舒服。
- [ ] 16. 确认/标准/复杂 dialog 宽度是否统一，窄窗表单是否可用。
- [ ] 17. 长列表 scrollbar 是否可发现，滚轮/拖动是否自然。
- [ ] 18. 各页 resize 及高 DPI 是否稳定，复杂表单是否无截断。
- [ ] 19. 整体是否像同一个 Jax 的桌面版，操作效率是否合适。

## 验收状态与停止边界

Record / Settings：migration implemented，awaiting real-device validation。
Windows：polish implemented，awaiting manual validation。
Design System migration 不标记 fully validated / completed，等待用户确认。Phase D 结束后停止 UI 迁移；未开展开源清理、README、License 或 GitHub 发布。本轮未安装到真机。

构建产物 SHA256（本机核对）：

- Android APK：`34e7caacfbebe9cef66e67412c7d5491fda907cacddd403c3380a0a5aaa41b91`
- Windows exe：`0f5473adba62b579d63693a5dc275bdedcba095f7e393fe76d0972cc86b33d22`
