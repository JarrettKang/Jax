# Planning Design Migration Report

Phase B1 · 2026-09-16  
规范：[Jax Design System v1.0](DESIGN.md)  
状态：**migration implemented / awaiting real-device validation**。不是 fully validated；未安装真机，未开始 World Phase B2。

## 范围与实现前审计

Planning Overview 与 Workspace 都位于 `lib/ui/pages/planning_page.dart`。原有概览已是轻列表并使用共享 ancestry；没有重新添加轮次、步骤统计或摘要。详情页仍有独立 `_WorldContext`，用 `└`、Colors.grey 和宽度比例缩进，与概览不一致。PlanItem 使用无卡片 ListTile，但 next 的圆圈具有待办勾选感，dropped 整行 opacity .55 也弱化 More。Quick Add 与 inline rename 交互已正确，原输入框所有状态均无边框，提交仍是 TextButton。Review 已渐进展开，但行底使用默认 Divider。

对应规范：安静、精确、克制的人格；26/17/16/14/13 字体层级；4/8/12/16/24/48 的实际间距；8 按钮圆角；连续画布；hairline 1 的必要分隔与 accent 2 焦点；情境化主按钮；稳定列表槽位；next/done/dropped/promoted 的文字与图标状态；Planning 保留思考空间；Android/Windows 同阶段验证。遵守 Exceptions，不把 Home Hero 或完整 World 树密度强加给 Planning。

## 修改文件与隔离方式

- `lib/ui/pages/planning_page.dart`：概览、详情、上下文、步骤、引用行、Quick Add、inline edit、Review、菜单和确认弹窗表现层。
- `lib/ui/theme/planning_theme.dart`：Planning 专用局部 Theme、页面 padding、输入边框、destructive 样式和 hover/focus 行容器。
- `test/ui/planning_design_migration_test.dart`：20 个双端/字号/页面布局场景，额外检查编辑、错误、键盘遮挡、引用改名、More 和键盘导航；可输出图片。
- `test/ui/planning_flow_test.dart`：保留所有断言，深列表滚动后等待布局稳定并确保 Quick Add 可点击；避免测试点击坐标落到视口外。
- `docs/DESIGN.md`：仅更新 Planning 实施/待验收状态与对应实现说明，没有修改正式 token。
- 本报告记录迁移与真机 checklist，不成为第二份规范。

局部主题复用现有 `HomePilot.theme` 中已被 DESIGN.md 采用的颜色、字号与按钮参数，并补 Planning 的输入/错误/边框样式。没有改动 HomePilot、本轮之外的页面、全局 `buildJaxTheme` 或共享 ancestry/tree 源码。代码中既有 pilot 命名未做跨页清理，不代表重新使用候选规范；视觉权威仍是 DESIGN.md。

## 1. Ancestry 与主标题

P0 已解决：删除旧 `_WorldContext`、字符树线、灰色硬编码和比例缩进，Overview / Workspace 均复用 `WorldNodeAncestryView`，不创建第三套树。

Overview 仍保留原有 Category + 全部上级链，不加入当前节点。Workspace 保留既有路径解析，在展示时去掉末尾当前节点；当前 WorldNode 由 26/600 主标题完整呈现，Category 和全部上级仍在 ancestry 中。没有按名称去重或丢弃同名祖先，也没有缩成单 parent。

ancestry 使用 13/400/1.45、textMuted、hairlineStrong，复用组件 12 缩进和最大 60 的上下文变体。完整 World 树未改。顶栏显示模块名“规划”，节点主标题移到可滚动正文，避免长名和大字号撑满 AppBar；现有关注和 More 操作仍在顶栏，route 不变。

## 2. PlanItem、marker 与状态

普通步骤保持连续行，无 Card、阴影、chip 或永久色块。概览节点标题 17，工作区标题 26，“计划步骤”17，行动标题 16，状态13。

原圆圈仅承担显示，没有点击或勾选行为。本轮改成中性 `short_text` 步骤标记，不增加完成交互。done 用普通勾，dispatched 用轻量关联说明，next 不重复显示“下一步”。没有引入“草稿”文案或新状态；旧内部类名/test key 的 draft 字样仅为兼容，未改业务模型。

dropped 移除整个 Opacity 包裹；标题用 textMuted，状态“ 不再需要 ”保持清楚，More 图标正常显示并可恢复。静止/编辑内容保留相同文字级别与水平内容 padding，编辑时新增动作占用必要纵向空间，不强行固定行高截断内容。

## 3. Promoted reference

保留 open/reference 图标、关联 WorldNode 当前名称和次级“世界节点”说明。仍调用既有关联解析与导航，不复制旧标题；目标改名的视觉更新有测试。缺失目标的原 fallback/提示不变。

引用行没有执行按钮或勾选标记，hover 与 keyboard focus 使用 Planning 行表面反馈；点击仍进入同一个既有目标工作区。

## 4. Quick Add 与 inline edit

Quick Add 仍是列表最后一行，静止无输入边框，以加号和“添加一步……”呈现。编辑采用轻量 8 圆角边框；focus 为 accent 2，错误为 error 边框和文字，不使用黑色实线。

添加/保存为 Filled Primary，取消为 TextButton；动作 Wrap 支持窄屏和大字号。输入正文16，与步骤同级，长文本允许多行显示，输入仍采用原 done/Enter 提交语义。原 Enter、Escape、失焦保存/取消、busy、错误和继续输入逻辑均保留。next 点击标题 inline rename，没有改为 modal；More 内原“编辑详情”弹窗仍保留。

编辑中的正文 padding 水平/垂直12，是 DESIGN scale 内的 Planning 变体；不改变 Home 的样式。模拟300逻辑像素键盘检查保存/添加可滚动到达，真实 Android 输入法候选栏与光标操作仍待验收。

## 5. Review、More 与 destructive

Review 保留摘要和展开查看机制；无记录时只有轻量标题与添加入口，不新增大空状态。标题17但用 textSecondary，内容14，时间/摘要13，低于当前节点和步骤。

计划步骤到 Review 使用唯一 hairline divider：stroke 1、布局高度25（上下12）。移除每条 Review 的默认 Divider，记录间用8留白；ExpansionTile 不再生成额外边框。

低频编辑、排序、放弃、提升、删除继续在 More，资格与回调保持不变。More 图标18、触控目标至少48，始终可见；删除/放弃菜单为 error，删除确认使用 destructive 色，普通完成不染成危险动作。未新增确认流程。

## 6. Token、平台与规范适配

采用 canvas `#F7F7F3`，textPrimary `#252A27`，textSecondary `#555E58`，textMuted `#68716B`，surfaceSubtle `#EFEFE9`，hairline `#DDE1DA`，hairlineStrong `#818B83`，accent `#315C4C`，accentSubtle `#E7EFEA`，error `#A33D36`。普通内容无独立 surface；菜单/modal 保留 Material 层次。

Android 左右16，Windows24，内容框上限820；不改变全局布局。两端按钮目标48，Windows靠横向布局和稳定槽位保持密度，不缩触控区域。hover 不改变位置，可点击文字/引用/概览行有独立 accent 焦点描边，焦点不表示 WorldNode 业务关注。

未发现必须修订 DESIGN.md token 的不适配点；caption、success 和完整 World tree 仍不在本轮验证范围。error/input/divider 在 Planning 有了实现和自动验证，但尚不据此宣布全局实机验收通过。

## 7. 自动验证与证据范围

- 静态检查通过，无问题：`build/planning-design-analyze.log`。
- 相关回归 **177 项全部通过**：Planning unit/data/widget、promotion、withdraw、review、rename、Quick Add、Home 往返及相关 World/Home 回归，见 `build/planning-design-regression.log`。
- 布局矩阵20场景：单/多节点 Overview；短/深路径 Workspace；无计划/空 Review；Android360×900 / Windows1200×900；1× / 2×系统字号。非空工作区含长 next、dispatched、done、dropped、promoted 和 Review。
- 场景内另外覆盖 inline edit / Escape、错误样式、300逻辑像素键盘遮挡、dropped More、关联目标改名、Review 展开。Windows 概览另验 hover 不移位、Tab焦点、Enter进入与返回。
- 既有真实 SQLite 测试验证 rename、创建、提升、drop/restore、执行关联、浏览零写入与 Home → Planning → 原 Category View；没有用截图替代业务测试。
- Android debug 构建与 Windows release 构建成功，日志：`build/planning-design-android.log`、`build/planning-design-windows.log`。Android 有工具链 native-access 提示，未阻塞构建，本轮未调整工具链。未安装、启动或清除真实设备数据。

按本轮开始时文件哈希核对，既有文件仅改了 Planning 页面、Planning flow 测试与 DESIGN 状态；Home、World、其他页面、共享组件、Core、Data、Sync 完全未改。没有提交 commit。

图片位于 `build/planning-design-qa`，是隔离数据和本机 QA 中文字体的离屏渲染，非 Android 真机截图。Windows 高 DPI、真实 IME、实际使用密度和鼠标体验仍需用户确认。

## 8. 真机验收 checklist

- [ ] WorldNode title 大小合适，长名称不挤压工作区。
- [ ] ancestry 完整且清楚，当前节点不重复。
- [ ] ancestry 没有过弱，深层 connector 可追踪。
- [ ] PlanItem 密度自然，静止/编辑的文字位置协调。
- [ ] marker 不再有明显可勾选待办感。
- [ ] Quick Add 像列表延伸，连续输入方便。
- [ ] inline edit 保存/取消、键盘及错误反馈自然。
- [ ] promoted reference 清楚，目标改名与导航正常。
- [ ] dropped 内容适度弱化，More 和恢复仍易发现。
- [ ] Review 足够轻，摘要/展开/编辑可用。
- [ ] divider 统一、不过深，也不多余。
- [ ] Android 小屏、大字号、输入法和底部安全区舒服。
- [ ] Windows 同属一套 Design System，hover/focus、Tab/Enter/Escape 和窗口缩放可用。

验收路径：Planning Overview → Workspace → next rename → Quick Add 连续添加 → More → promoted 引用 → 返回；另检查 Home Category → 规划一下 → 返回原 Category/滚动位置。仅在测试数据上试验删除/放弃等操作。

完成后停留在 B1；收到用户真机反馈后再决定是否标记 validated，以及何时开始 B2。

## 离屏预览

- [Android 概览与深 ancestry](../build/planning-design-qa/overview-many_android_1.0_initial.png)
- [Android 工作区](../build/planning-design-qa/workspace-short_android_1.0_initial.png)
- [Android 行内编辑](../build/planning-design-qa/workspace-short_android_1.0_inline.png)
- [Android Quick Add 错误反馈](../build/planning-design-qa/workspace-short_android_1.0_quick-add-error.png)
- [Android dropped More](../build/planning-design-qa/workspace-short_android_1.0_dropped-menu.png)
- [Windows 概览键盘焦点](../build/planning-design-qa/overview-one_windows_1.0_focus.png)
- [Windows Review 展开](../build/planning-design-qa/workspace-short_windows_1.0_review.png)
