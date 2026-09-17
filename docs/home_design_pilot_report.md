# Home Design Pilot Report

> 后续状态补记（2026-09-16）：Pilot 之后已按用户要求覆盖安装 Android 真机，用户确认整体体验可以接受，可继续沿此方向推进。正式视觉规范已固化为唯一的 [Jax Design System v1.0](DESIGN.md)。以下正文保留 Pilot 完成当时的实验与验证记录，其中“未安装”“等待确认”描述当时状态，不是当前状态。原 checklist 未逐项签收，Windows 实机主观验收仍未记录；后续以正式规范的 Validation Status 为准。

日期：2026-09-16。状态：Home 局部实验，等待真机使用与用户确认；不是正式 DESIGN.md。

## 范围与代码

- `lib/ui/pages/home_page.dart`：Root、Temporal Recommendation、Running Event / Routine、Category View 的表现层。
- `lib/ui/theme/home_pilot_theme.dart`：实验颜色、字体、按钮、圆角、宽度与 hover 容器。只由 Home 引用，不改全局 `buildJaxTheme`。
- `lib/ui/widgets/execution_action_buttons.dart`：增加可选 `primary` / `style`，原默认值不变。
- `lib/ui/widgets/world_node_ancestry_view.dart`：增加可选 `textStyle` / `guideColor`，原默认值不变。
- `test/ui/home_design_pilot_test.dart`：四态矩阵、文字缩放、触控高度、主题隔离、promoted 排除、键盘、hover 与共享默认样式验证；支持输出渲染图。

共享动作组件仍供 Today、Routine 等页面使用；ancestry 仍供 Planning 概览使用。它们没有传入新参数，因此本轮不改变其默认外观。Home 内部使用局部 Theme，AppBar、导航壳和通过既有路由打开的 Planning 保持原主题。

查询、推荐排序、状态转换、事件创建、去重、导航状态、滚动保存、assistantName、JaxDay、数据库与 Sync 没有进行本轮修改。工作区原有未提交改动保留，没有提交 commit，也没有安装或启动构建产物。

## 1–3. 使用的候选 token、调整及原因

采用候选 canvas、surface、surfaceSubtle、textPrimary、textSecondary、textMuted、hairline、hairlineStrong、accent、accentSubtle、warning；白色同时用作 onAccent。只提供 Home 实际需要的角色，不创建全局 Jax token API。

候选色值没有改动。调整的是语义角色与场景选择：

- ancestry 从原有 11 号 + 透明度改为 13 号实色 textMuted，树线使用 hairlineStrong，避免细线过弱。
- Running 的「正在执行」采用 textSecondary：textMuted 在淡绿色背景上仅约 4.31:1，换成 textSecondary 后更清楚。
- Windows 没有缩小按钮至 36–40，保留两端至少 48 的最小目标，让触屏设备也能使用。密度通过排列方式实现。
- 不使用候选 4 号圆角，也不为普通行添加圆角或外框；没有必要的 divider 就不画。
- 普通行动行根据宽度、执行状态与字体缩放选择横排或纵排；没有缩小标题或触控面积。

## 4. Canvas 与颜色

| 角色 | 最终实验值 |
|---|---|
| canvas | `#F7F7F3`，覆盖整个 Home 内容区域 |
| surface / onAccent | `#FFFFFF` |
| surfaceSubtle | `#EFEFE9`，普通行动行 hover |
| textPrimary / textSecondary / textMuted | `#252A27` / `#555E58` / `#68716B` |
| hairline / hairlineStrong | `#DDE1DA` / `#818B83` |
| accent / accentSubtle | `#315C4C` / `#E7EFEA` |
| warning | `#865C19`，只用于逾期推荐说明 |

计算的 sRGB 对比度：主文字/画布 13.59:1、次级文字/画布 6.25:1、metadata/画布 4.70:1、warning/画布 5.49:1、白字/accent 7.59:1、hairlineStrong/画布 3.28:1。数值不能替代真实屏幕上对字体、抗锯齿与细线的判断。

画布暂时保留原候选值：离屏图上层级自然，还没有 Android 真机证据证明需要调冷或调暖。白色 surface 没有作为推荐卡片投入使用，因此白卡与画布的组合不算本轮已验证规则。

## 5. Typography

| 用途 | 字号 / 字重 / 行高 |
|---|---|
| 问句、推荐标题、分类页标题、Running 标题 | 26 / 600 / 1.30 |
| WorldNode 组标题 | 17 / 600 / 1.40 |
| 行动标题、Category 入口 | 16 / 500 / 1.45 |
| 管家名称、一般正文 | 14 / 400 / 1.50 |
| 问候、推荐引导、时间信息、状态、ancestry | 13 / 400 / 1.45 |
| 按钮文字 | 14 / 500 / 1.40 |
| Running 计时 | 32 / 500 / 1.30，等宽数字 |

26 号问句在 360 宽、正常字号下保持单行，离屏图没有营销大标题的占屏程度，故本轮保留。长标题自然换行，Running 不再截断为两行。中文零字距，继承平台字体；不覆盖全局字体。

保留系统文字缩放。极长计时在大字号下保持单行，可横向查看，避免秒数独自折到下一行；这项交互仍需真机确认是否合适。

## 6–7. Spacing 与 Radius

主要间距沿用 4、8、12、16、24、48：状态与 ancestry 附近 4；文字、图标及动作换行 8；按钮水平内边距与动作间距 12；主要文字到按钮 16；分组、问候到决策区、Hero 内边距 24；页面底部留白 48。本轮没有强行使用每个候选数值，32 不是必需。

手机页边距 16，Windows 24，阅读宽度上限 820。普通行动行上下各 8；WorldNode 组间 24，使用留白而非 divider。

按钮圆角 8；Running Hero 圆角 16；普通行保持直角、透明连续背景。Home 内容无阴影。

## 8–10. 按钮、Recommendation、Running

- Recommendation 不用独立 surface：管家引导为 metadata，事项名为唯一主标题，时间说明次级，Filled「开始」为唯一主动作。
- 「或者做点别的」与分类入口使用留白隔开；分类色仅保留身份小色点。
- 普通列表的开始、继续、完成全部为 Outlined，避免每行重复强填充。规划、临时事项和等待查看是 TextButton。
- Running 是唯一独立强调 surface：accentSubtle + 16 圆角，没有分类色边框、阴影或大状态图标。
- Running 的暂停为 Filled；等待、完成和校正时间仍在既有更多菜单，未重排业务动作或新增执行路径。暂停按钮按内容宽度显示，不再横向铺满 Hero。
- Hover 不改变尺寸；普通行动行使用 surfaceSubtle。键盘焦点采用 accent 2 像素描边。主按钮获得焦点时转为浅底深字，让描边清晰可见。

## 11–12. Ancestry 与 Category View 密度

继续复用共享 ancestry 与绘制树线。Home 覆盖为 metadata 13，不叠透明度；12 缩进、最大 5 层可视缩进保持原实现，所有深层文字完整显示。超过 5 层时缩进封顶，这一既有行为未改变。

层级为 26 号 Category → 17 号 WorldNode → 13 号 ancestry → 16 号行动。组级「规划一下」保持轻量。

普通行动行不加卡片、分隔线或状态 chip。暂停/等待有小图标与中性状态文字。单动作在可用宽度至少 320 且文字缩放不大于 1.25 时横排；双动作在宽度不足 480 时换行；大字号统一纵排，避免标题被操作挤压。等待提示在分类内容之后，保留中性提示与查看入口。

## 13. Android / Windows

两端使用同一颜色、字体层级、按钮规则、48 最小触控目标。区别主要是页面边距和自适应排列；Windows 有 hover、Tab/Enter 与 Escape。

测试画布为 Android 360×900、Windows 1200×900，各有 1× / 2×文字缩放。渲染图使用真实应用主题与隔离数据，加载本机 Microsoft YaHei 字体及 Material Icons 以便检查中文和图标；不是 Android 系统字体或物理设备截图。测试中的 AppBar 是简化壳；实际导航壳另外通过现有测试验证。

## 14–16. 推广候选、待验证与刻意未解决事项

值得继续验证的规则：情境化主按钮、固定 metadata 语义色、13 号 ancestry、分类身份和执行状态分离、连续画布、局部单一强调面、宽度与字号驱动的动作换行。

仍待真机：微暖底色是否脏黄；26 号问句是否过强；13 号 metadata 在实际屏幕是否清楚；按钮描边与 primary 重量；深 ancestry 的追踪体验；长计时横向查看；Windows 高 DPI、Android 系统字体与系统导航栏避让。用户认可前不将这些值升级为全局标准。

刻意不解决：其他页面样式差异、全局 AppBar/导航壳配色、Planning 详情 ancestry、Today 暂停/等待行一致性、dropped 透明度、统一全局宽度、深色模式、success/error 体系、正式 DESIGN.md、Home 等待详情页的完整重设计。

## 验证记录

- `flutter analyze`：最终检查无问题，见 `build/home-pilot-analyze.log`。
- 最终相关测试共 **68 项，全部通过**，见 `build/home-pilot-final-tests.log`。
- 新增 36 个布局场景（9 场景 × 2 平台 × 2 缩放）及 1 个共享默认样式测试。
- Root：无分类、单分类、多分类、长名、等待有/无。
- Recommendation：active、overdue、多分类、长 Routine 名称。
- Running：Event / Routine、长标题、123 小时计时；暂停/等待操作由既有 Home 回归验证。
- Category：单/多 WorldNode、8 层 ancestry、无 ancestry、空分组、多行动、暂停、等待、promoted 排除。
- 既有 Home 回归覆盖推荐切换、规划往返、分类滚动保存、执行生命周期、名称设置；额外检查共享 ancestry 与应用导航壳。
- Android debug APK 与 Windows release 均按要求构建；未安装。构建日志保留在 `build/home-pilot-android.log` 与 `build/home-pilot-windows.log`。
- Android 构建存在 JDK native-access 提示；构建成功，未在本轮改动工具链。
- 全部自动验证仅使用测试数据，没有操作用户数据库。

## 真机验收 checklist

- [ ] 背景舒服，没有脏、黄、旧的感觉。
- [ ] 问句 26 号清楚，但不过强。
- [ ] 分类入口轻量，长名称完整且容易点击。
- [ ] 时间推荐比自主选择更突出，逾期提示不过度警告化。
- [ ] Filled 主按钮不过重。
- [ ] Running 明显但不浮夸，长计时可读，暂停/等待/完成可用。
- [ ] ancestry 清楚，深层结构仍能追踪。
- [ ] PlanItem 不过密或过松，双动作换行自然。
- [ ] metadata 不过小或过浅。
- [ ] 等待提示容易找到，分类页底部位置可接受。
- [ ] Android 小屏、系统大字号与底部导航避让自然。
- [ ] Windows 高 DPI、hover、键盘焦点与 Tab/Enter/Escape 正常，仍像同一个产品。

附加导航复核：Root → Category → Planning → 返回 Category（滚动位置保留）→ Root；Running 结束后上下文与推荐切换行为保持。

## 离屏渲染预览

以下为测试数据生成的布局图，不是真机截图。完整输出位于 `build/home-pilot-qa`，包括正常 / 2 倍文字、空状态、焦点与 hover。

- [Android Root](<project-root>/build/home-pilot-qa/root-many_android_1.0.png)
- [Android active 推荐](<project-root>/build/home-pilot-qa/active_android_1.0.png)
- [Android overdue 推荐](<project-root>/build/home-pilot-qa/overdue_android_1.0.png)
- [Android Running Event](<project-root>/build/home-pilot-qa/event_android_1.0.png)
- [Android Category](<project-root>/build/home-pilot-qa/category-single_android_1.0.png)
- [Android 深 ancestry](<project-root>/build/home-pilot-qa/category-deep_android_1.0.png)
- [Windows Running Routine](<project-root>/build/home-pilot-qa/routine_windows_1.0.png)
- [Windows 行 hover](<project-root>/build/home-pilot-qa/category-deep_windows_1.0_hover.png)
- [Windows 键盘 focus](<project-root>/build/home-pilot-qa/root-one_windows_1.0_focus.png)
