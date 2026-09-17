# World Design Migration Report

## 修改前只读审计（2026-09-16）

以 docs/DESIGN.md v1.0 和本轮开始时实际代码为准。

| 项目 | 当前实现与判断 | 本轮处理 |
|---|---|---|
| 主页面 | Scaffold + ListView；12/8 页边距，无宽度限制 | 局部主题，Android 16 / Windows 24；结构区上限 1040 |
| Category | ListTile，色点，48 行高；名称单行截断、根数量挤在标题旁、默认 Divider | 保留 section 和色点；17 标题自然换行，移除常驻数量及逐区线，用留白 |
| WorldNode | WorldNodeBrowsingRow；主体、展开、More 为兄弟点击区 | 保留分区、48 目标；16 正文，自然换行 |
| 展开与顺序 | parent 单击展开；本地 collapse store 持久化；sortOrder/id 稳定排序 | 不改 |
| connector | 共享 WorldNodeTreeGuideFrame；1px，outlineVariant × .9；父轴/短横支线 | 显式 hairlineStrong，保持 1px；可选封顶延续绘制，不改旧默认 |
| root/child/deep | base0 / 每层16 / 最大7层=112；名称最多2行 | 每层16，最大可视3层=48；超过后显示真实层级与完整父名 |
| focused | 12号 center_focus_strong + outline 色 | 16号实色 textMuted 图标；parent 同时保留 chevron |
| completed | leaf 勾圈 + outline 文字 + 删除线；parent 无独立完成图标 | 中性勾 + 次级字；移除删除线，展开/More/线条保持对比 |
| hover/keyboard/selected | InkWell 默认反馈，无明确 keyboard outline；主树无 selected 状态 | hover subtle；keyboard accent2；业务关注仍独立小标记 |
| More | 节点 icon18/目标48，持续可见；分类 More 默认样式 | 同一中性色、48目标、tooltip；动作资格不变 |
| Move Picker | 共享 picker，也被 Planning 使用；12+18缩进/最大7、40目标、名称2行 | World 显式 opt-in 视觉变体；Planning 默认不变 |
| Add child / Rename | 名称对话框，Enter提交，取消/保存，错误由 guard snackbar 显示 | 保留流程，8圆角输入、明确边界、16输入字和自然换行 |
| Delete | 仅分类删除有确认；节点 More 没有 delete 能力 | 分类删除 error 文字与确认按钮；不新增节点删除 |
| Complete / Restore | controller 管理；restore 不自动 focused | 不改逻辑，复测 |
| promoted | World 主树没有来源标签 | 保持普通节点 |
| metadata | 主树仍显示 当前计划 / N个下一步，根节点数量 | 去除这些常驻显示；计划详情和历史入口保留 |
| 平台 | 同一布局，尚无本页明确平台密度/宽度策略 | 保留48，两端页边距不同；Windows短行保持紧凑 |
| 硬编码 | 字号16/权重600或400；focus12；leaf8/16；缩进16；padding12/8/6/18；默认Divider；无普通卡片圆角 | 依规范语义替换，几何缩进作为 World contextual variant 记录 |

已符合：连续画布、无节点卡、无双击、More 始终可见、根/兄弟排序、48节点操作目标。历史视觉主要是截断、删除线、默认线色与默认控件样式。Planning ancestry 是只读上下文，World 是管理完整树，不能复用完整 ancestry widget；仅共享已有 painter 与正式 palette。共享可选参数默认保持不变，不改变已验收 Planning/Home 的绘制。

以下为本轮最终实施与验证结果。

## 实施结果

状态：**migration implemented / awaiting real-device validation**。Planning 的 Android 真机第一轮已按用户本次确认更新为 validated；Windows 主观验收不推定通过。

### 文件与 widget

- `lib/ui/pages/world_page.dart`：主树、Category、More、名称与删除分类对话框、Move Picker 入口。没有改 controller 调用、候选规则、排序或生命周期逻辑。
- `lib/ui/theme/world_theme.dart`：World 局部主题与结构参数、WorldRowSurface。复用已采用的 HomePilot/PlanningTheme token 实现，不改它们或全局 Theme。
- `lib/ui/widgets/world_node_browsing_row.dart`：保留原来的三个点击分区；标题可完整换行，键盘 focus 与 hover 仅改绘制。
- `lib/ui/widgets/world_node_tree_guide.dart`：新增 opt-in 的封顶连接与前景绘制；旧默认不变，World hover 不遮挡树线。
- `lib/ui/widgets/world_node_tree_picker.dart`：World 显式开启 `worldVisuals`；可选 header 同候选一起滚动。Planning 默认路径保持原布局。
- `lib/ui/pages/world_node_detail_page.dart`：局部主题、模块 AppBar、完整节点标题、section 字体/分隔；计划与执行历史仍属于详情，不移回主树。
- 新增 `test/ui/world_design_migration_test.dart`、`test/ui/world_design_actions_test.dart`；更新既有 `compact_world_map_test.dart`、`world_planning_workflow_test.dart` 的已过时显示断言与滚动定位。
- `docs/DESIGN.md`：World 实施状态和明确限定的场景参数；Planning Android 验收状态。未重写全局规则。

### Category / 节点与状态

Category 是 sectionTitle 17，小色点只表身份；不用卡片、色块、阴影或常驻根数量。节点标题16，parent500/leaf400；短行48，长名增高。Category间24留白，空态与内容左对齐。More始终可见，视觉18、目标48。

| 状态 | 实施后的视觉 | 行为 |
|---|---|---|
| expanded / collapsed | 独立18号 chevron，展开时显示连接线和子树 | parent主体与chevron均保持原展开/折叠 |
| business focused | 16号实色中性关注标记；可与parent chevron共存 | leaf单击关注/取消；parent从More管理关注 |
| completed | 中性勾 + textMuted；无删除线、无整行opacity | completed leaf无操作；parent仍能展开；More保持可用 |
| restored | 正常正文，不显示关注标记 | 恢复不会自动focused |
| hovered | surfaceSubtle，几何不变，connector仍在前景 | 鼠标反馈，不成为唯一管理入口 |
| keyboard focused | accent2轮廓，不改变行尺寸 | 原Tab/Enter/Space语义；不修改业务关注 |
| selected | 主树没有常驻selected状态；picker选择立即提交已有移动流程 | 不增加选中模型或确认步骤 |

主树移除原先的“当前计划 / N个下一步”。未增加promoted来源、milestone或统计。节点More没有删除能力，本轮也没有新增。分类删除仍使用既有确认，error文字及error确认按钮；取消不写入。

### Connector / 缩进与深树

同源使用既有几何 painter，hairlineStrong `#818B83` / 1px。父轴、短横分支、兄弟延续按原真实树上下文绘制。完成/关注不改变线色。超过缩进上限时沿压缩轨道连续绘制，通过“第N层 · 上层：完整父名”消除同列不同深度的歧义。

每层16，默认最多3个缩进槽=48。按实际可用宽度与文字缩放，在1–3个槽之间收缩，尽量保留约5个标题字宽；320宽/2×字号缩为16。不持续缩小字号，也不截断名称。封顶只影响显示，parentId、路径、顺序和任意真实深度均保留。

这是 World 完整树的 contextual variant，已写入 DESIGN.md §11/§19。Planning/Home 的只读 ancestry 仍为其原有紧凑参数，未使用完整World row。共享 primitive 的新选项默认关闭，旧picker默认不启用World主题。

### Move Picker / 编辑 / 详情

Move Picker纳入轻量迁移：Category→完整可折叠树、48目标、同源线条、完整名称、明确禁用说明。源节点名、顶级目标和候选位于同一滚动区，小屏大字号不会被固定说明区挤掉。本人、后代、当前父级等禁用条件，以及移动后的分类/排序计算全部保留。

名称对话框仍是原工作流：Enter/保存提交、取消/返回退出；输入16、8圆角、1px边界、2pxfocus，自然换行；内容可以滚动以避让软键盘。错误仍通过现有guard/snackbar路径显示，没有改为另一套保存或验证流程。World详情采用相同局部视觉，保留真实计划、历史和执行记录。

### 平台与 token

Android / Windows页边距16 / 24；结构区上限1040，避免宽窗无限拉散，不套用Planning820。两端默认目标均48；Windows不另引入未经验证的36–40鼠标小目标。高密度主要来自单行连续树、无常驻统计和无卡片，而不是缩小操作区域。320/390手机、480/1400桌面与1×/2×字号已覆盖。

采用：canvas、surface、surfaceSubtle、textPrimary/Secondary/Muted、hairline/hairlineStrong、accent、error；pageTitle26、sectionTitle17、itemTitle16、metadata13；4/8/12/16/24/48间距；输入和按钮medium8、普通行none；线1、键盘focus2；状态icon16、操作icon18、目标48。modal/menu允许独立表面，沿用Material浮层层次。

## 自动验证

最终命令与结果见本报告后续“最终验证结果”。新增矩阵24组，额外2组SQLite真实操作；中文离屏字体仅用于QA，不改变产品字体策略。

重点回归：parent/leaf/completed点击语义、无double tap、关注不改执行事实、恢复不自动关注、移动候选禁用和reparent、类别/分支折叠保存、Planning共享picker及ancestry。新增SQLite测试确认重命名/添加/完成/恢复/分类删除期间plans、plan_items、events、run_segments、dataset_metadata保持原事实。

### 可查看的离屏预览

- [Android 树与状态](../build/world-design-qa/tree-android-390-1.0.png)
- [Android 深树](../build/world-design-qa/deep-android-390-1.0.png)
- [320宽 / 2×字号深树](../build/world-design-qa/deep-end-android-320-2.0.png)
- [320宽 / 2×字号移动](../build/world-design-qa/move-android-320-2.0.png)
- [大字号软键盘编辑](../build/world-design-qa/keyboard-320-2.0.png)
- [Windows 宽窗键盘焦点](../build/world-design-qa/focus-1400-1.0.png)
- [Windows 窄窗](../build/world-design-qa/tree-windows-480-1.0.png)

## World 真机验收 Checklist

- [ ] Category清楚但不抢眼，多分类和长分类名容易分辨。
- [ ] WorldNode密度合适，普通短行不松散、长行不拥挤。
- [ ] Parent/child关系一眼可读，展开与折叠清楚。
- [ ] Connector不太浅或太重，滚动与hover后保持连续。
- [ ] 6–9层结构仍可读，封顶后的层数/父名提示足以辨认关系。
- [ ] 长名称、多行名称与系统大字号阅读舒服。
- [ ] Focused标记清楚但低噪声。
- [ ] Completed节点仍可阅读，完成parent仍能展开。
- [ ] Parent关注标记与展开图标不混淆，恢复后没有误显示关注。
- [ ] More始终容易找到和点击，包括深层与完成节点。
- [ ] Android点击区、滚动、软键盘、系统返回和底部导航使用舒服。
- [ ] Windows宽窄窗口、hover、Tab、Enter/Space和More反馈自然。
- [ ] 整体像长期结构地图，没有变成任务统计或卡片列表。
- [ ] 与Home/Planning属于同一设计语言；Move Picker和编辑对话框连贯。

仍待验证：实际Android中文字体、屏幕和触控观感；真实长树规模下滚动体验；用户是否认为深层父名提示过密；Windows实机鼠标/键盘和高DPI观感。离屏与自动测试不替代这些主观验收。

本轮完成后停在B2，不进入Today/Routine/Record/Settings；不自动标记Phase B整体完成。

## 最终验证结果

2026-09-16，最终生产代码完成后：

| 验证 | 结果 | 本地记录 |
|---|---|---|
| flutter analyze | No issues found | `build/world-design-analyze.log` |
| World/hierarchy/focus/complete/restore/move + Planning/shared picker + Home ancestry等相关回归 | 175 passed | `build/world-design-regression.log` |
| 导航壳/手机底部导航/宽窗响应式 | 3 passed | `build/world-design-shell.log` |
| 中文离屏矩阵及SQLite新增操作 | 26 passed（24布局+2操作，已包含在175中，不重复计数） | `build/world-design-visual.log` |
| Android debug build | 成功，9.6s | `build/world-design-android.log` |
| Windows release build | 成功，24.6s | `build/world-design-windows.log` |
| diff whitespace检查 | 通过 | 本轮修改文件 |

相关测试合计178项通过。Android仅有Gradle/native-access工具链提示，不影响构建。APK位于 `build/app/outputs/flutter-apk/app-debug.apk`；Windows位于 `build/windows/x64/runner/Release/jax.exe`。本轮没有安装到真实数据设备、没有提交Git。

开始时保存文件哈希至 `build/world-design-before.json`。最终核对变更仅为本报告列出的World页面/组件、共享primitive的可选参数、相关测试与DESIGN文档；Home/Planning页面与theme、其他页面、Core/Data/Sync未变化。共享picker原默认布局仍通过Planning回归。

## Android 覆盖安装记录

Private device rollout evidence omitted from this historical version.

