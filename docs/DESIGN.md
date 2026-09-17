# Jax Design System

**Version 1.0 · 2026-09-16**  
**Scope：Light mode · Android · Windows**  
**Dark mode：Not yet defined。不得通过浅色反转自动生成。**

本文件是 Jax 唯一 canonical UI 视觉规范，适用于后续 Home、World、Planning、Today、Routine、Record、Settings 的开发与重构。外部设计参考和历史试验报告不再作为并列规范。产品行为以 [PRD](../PRD.md) 与现有 Core 规则为准；开发阶段以 [开发计划](../Development_plan.md) 为准。视觉迁移不得借本规范改变业务行为。

v1.0 根据只读设计审计、Home 最终实现、[Home Pilot Report](home_design_pilot_report.md) 及用户 Android 真机第一轮主观验收固化。**规范生效不等于所有页面已迁移，也不等于所有 token 均已实测。**

规则来源标记贯穿全文：

- **A — Home 已验证基础**：在 Home 实现并通过相关测试、离屏检查，用户认可 Android 整体体验；可作为全局迁移依据。不是每项参数均获独立主观验收，其他页面仍须验证适配。
- **B — 后续页面实施时验证**：v1.0 的基础设计约定，Home 未充分验证；迁移时须检验实际用途与参数。
- **C — 场景限定**：只在所述页面或交互中适用。其验证状态另行说明，不提升为所有页面的默认布局。

## 1. Design Personality

Jax 是安静、精确、有温度、克制、可靠的个人电子管家。它服务于长期每天使用：信息复杂时仍保持有序，需要行动时下一步清楚，需要思考时有足够空间，主动表达时带有适度温度。

温度来自体贴的措辞、清晰的上下文和合适的留白。避免企业 Dashboard、营销展示页、聊天机器人、游戏化生活应用的视觉惯性，也不复制任何参考产品的界面。

## 2. Core Principles

1. 内容与行动优先；先用 typography、spacing 和位置表达层级，再考虑容器、颜色或线条。
2. 同一语义使用一致表达；不同工作场景可以有不同密度。决策区域舒展，执行列表紧凑，结构视图有序。
3. 一个局部动作组最多一个强主按钮；页面当前任务应有清楚的视觉第一层。
4. Category 色表示身份，执行色表示状态，两者独立。时间推荐状态与执行状态也是两个维度。
5. 状态优先用文字，再用图标和少量颜色辅助。颜色、hover 和透明度都不能成为唯一信息载体。
6. Android / Windows 同步验证。统一语义、层级和视觉语言，不强求完全相同的像素布局。
7. 关键文字、操作与真实历史不可为视觉整齐而隐藏或改写；保留导航上下文、保存反馈与键盘可用性。

业务保护边界：保留 JaxDay 23:00 分界、Temporal 三时间与跨日 occurrence、既有推荐排序、状态转换及资格查询。waiting 不计主动执行时长；恢复沿用 execution 并新开 segment；paused 直接完成不补造时长。未结束的 paused/waiting 不因过期或跨日自动消失。PlanItem 开始时创建关联 Event，不能重复创建/展示；promoted reference 只导航。Record 展示真实 RunSegment。数据库、Sync、保存和导航行为不由本规范重新定义。

## 3. Design Tokens

数值使用 Flutter 逻辑单位；字号是未应用系统文字缩放的基准值。以下是正式设计语义，不要求已有代码立即改名或全局替换 Theme。迁移应小步接入，避免影响尚未迁移页面。

### Color

| Token | v1.0 值 | 使用位置 | 不应使用的位置 | 依据 |
|---|---|---|---|---|
| canvas | `#F7F7F3` | 页面连续画布 | Category 色块、状态警报底 | A |
| surface | `#FFFFFF` | 必要独立交互表面 | 普通事项逐行铺白卡 | B：独立白色表面未在 Home 主内容验证 |
| surfaceSubtle | `#EFEFE9` | 轻量 row hover；必要中性分区 | running、overdue 的身份标记 | A：hover；其他用途 B |
| textPrimary | `#252A27` | 当前事项、标题、主要内容 | 所有 metadata 一律加重 | A |
| textSecondary | `#555E58` | 正文、辅助说明、Hero 小字 | 禁用状态的唯一信号 | A |
| textMuted | `#68716B` | 画布上的时间、状态、ancestry 等上下文 | 浅色叠透明度；未经检查的有色底小字 | A |
| hairline | `#DDE1DA` | 低强调结构分隔 | 键盘焦点、必须清晰的控件边界 | B：有 token，Home 未实测 section divider |
| hairlineStrong | `#818B83` | 按钮/输入边界、需可辨认的 connector | 普通文本、全页密集格线 | A：按钮和 ancestry；输入 B |
| accent | `#315C4C` | Primary、键盘焦点、必要执行强调 | Category 身份；所有状态统一染绿 | A |
| onAccent | `#FFFFFF` | accent 实底上的文字/图标 | accentSubtle 上的正文 | A：代码复用 surface 值，语义独立 |
| accentSubtle | `#E7EFEA` | Running 强调面、Primary 聚焦浅底 | 每个普通行或每个推荐统一铺底 | A，表面用途受 C 限定 |
| success | `#3F6B50` | 确有必要的操作成功反馈 | completed 整行绿色、普通历史 | B：沿用审计候选，后续验证 |
| warning | `#865C19` | overdue 时间说明、需注意的轻提示 | waiting 默认色、整块警报背景 | A：overdue；其他用途 B |
| error | `#A33D36` | 错误说明、破坏性动作 | 一般延期、过期、历史完成 | B：沿用审计候选，未替换现有全局 error |

Category 色继续取现有集中分类色板，用于小色点和记录图表的身份编码。不得承担 running、paused、waiting、overdue、completed 的状态含义；图表仍需文本/图例。

文字使用明确语义色，避免整行 opacity 或逐层叠透明度。计算对比度：textPrimary / canvas 约 13.59:1、textSecondary / canvas 6.25:1、textMuted / canvas 4.70:1、warning / canvas 5.49:1、onAccent / accent 7.59:1。textMuted / accentSubtle 仅约 4.31:1，因此 Hero 小字使用 textSecondary。不同背景组合须重新检查，不能仅凭 token 名认定可读。

透明色可用于无表面状态、控件交互叠层或不可见的占位描边；它不是另一套结构边框色。Home 按钮 hover 使用 accent 8% 叠层，这不授权对文字使用低 opacity。

### Typography

| Token | 字号 | Weight | 行高 | 用途与状态 |
|---|---:|---:|---:|---|
| pageTitle | 26 | 600 | 1.30 | 页面内容主标题、当前主事项；A |
| sectionTitle | 17 | 600 | 1.40 | WorldNode 组标题、分区标题；A |
| itemTitle | 16 | 500 | 1.45 | 行动名称、轻量分类入口；A |
| body | 14 | 400 | 1.50 | 一般正文、管家身份；A |
| metadata | 13 | 400 | 1.45 | 时间、状态、ancestry、轻引导；A |
| caption | 12 | 400 | 1.40 | 非关键短注释、图表辅助标签；B，Home 未定义独立角色 |
| actionLabel | 14 | 500 | 1.40 | 按钮文字；A |
| timer | 32 | 500 | 1.30 | 等宽数字计时；C，Home 已实现 |

pageTitle 指内容主层级，不强制把平台 AppBar 标题也改为 26。中文基准字距为 0，不采用营销式负字距。优先自然换行，不靠 11 号字、低 opacity 或缩小触控目标获得密度；关键上下文不降为 caption。

保留系统文字缩放，不全局锁定 scale 或压缩字号。Windows 延续 Microsoft YaHei UI 和系统 fallback；Android 继承平台默认字体和中文 fallback，不强制使用 Windows 字体。离屏测试加载的 QA 字体不是产品字体策略。

### Spacing

正式 scale 为 **4 / 8 / 12 / 16 / 24 / 32 / 48**，按语义选取，不机械要求所有尺寸都为 scale 成员。

| 值 | 默认用途 | 验证状态 |
|---:|---|---|
| 4 | 标题旁状态、紧邻 metadata | A |
| 8 | 相关元素、图标与文字、动作换行 | A |
| 12 | 行内动作间距、按钮水平内边距 | A |
| 16 | Android 横向页边距、普通内边距、说明到动作 | A |
| 24 | section 间隔、Windows 页边距、Home Hero 内边距 | A |
| 32 | 需要更明确分隔的主决策区域 | B：Home 未采用，不要求补用 |
| 48 | 页面底部舒展留白；大空状态周围空间 | A：Home 底部留白；空状态用途 B |

允许 1–2 逻辑像素的光学校正，但须说明用途，不能借此产生新的任意间距体系。Home ancestry 每行上下各 1 是既有紧凑变体，不是普通行动行密度标准。48 的间距与 48 的触控目标属于不同语义。

### Radius

| Token | 值 | 适用范围 | 状态 |
|---|---:|---|---|
| small | 4 | 必要的小型独立控件 | B：尚未在 Home 使用 |
| medium | 8 | 按钮；输入或必要轻表面 | A：按钮；输入/表面 B |
| large | 16 | Running Hero 等明确指定强调面 | C：Home 已验证；其他场景须论证 |
| none | 0 / 无容器 | 普通 WorldNode、PlanItem、Today/Event/Routine/Settings 行、ancestry | A 的连续画布原则，其他页面迁移 B |

统一视觉不意味着为以上普通内容增加 Card；large 不是“重要内容”的默认圆角。

### Surface

默认连续 canvas。允许独立 surface：Running Hero、确有需要的单一主要 Recommendation、modal、menu、popover，以及拥有真实独立交互边界的内容。

Home Recommendation 已选择**无独立 surface**，仅通过字号、间距与动作强调；不要为了满足“允许”而加卡。Home 主内容最多一个主要强调面，Running 优先。其他场景的 Recommendation surface 属 B，迁移时验证必要性。

普通 WorldNode、PlanItem、Event、Routine、Settings、ancestry、Category 列表默认不 Card 化。必要 hover、selected 或 focus 反馈不等于永久容器。

### Divider / Border

颜色、stroke width、周围留白分别定义。Flutter `Divider.height` 是占用的布局高度，`thickness` 才是线宽；不得把两者混用。

| 类型 | 颜色 | 线宽 | 周围空间 / 使用条件 | 状态 |
|---|---|---:|---|---|
| Section divider | hairline | 1 | 先用 section 留白；确需线时上下各 12 为起点，不再重复叠加同义间距 | B |
| Row divider | hairline | 1 | 连续行默认无；有歧义才加线，保留原行 padding，不人为加高 | B |
| Hierarchy connector | Home compact 用 hairlineStrong | 1 | 占层级缩进槽；不当作 section divider | C：Home 已验证；完整 World 树 B |
| Input border | hairlineStrong；错误时 error | 1 | medium 圆角，正文内边距起点水平 12 / 垂直 8 | B |
| Keyboard focus outline | accent | 2 | 占位稳定，hover 不使用同等轮廓 | A：Home 按钮；其他控件 B |
| Running marker | accent | 2（可选） | 仅紧凑列表必要时；Home Hero 不使用 | B/C：不是全局强制标记 |

不依赖未配置的默认 Divider、黑线或任意灰线。Home 分组仅用留白，不能声称其验证了所有 divider 参数。控件若以透明 border 保留焦点占位，允许采用；不得拿透明边框充当可见结构边界。

### Elevation

普通页面、普通行、Running Hero 的 elevation 为 0（A）。菜单、浮层和模态框可用 elevation（B），优先保留平台 Material 的适当层次，不自创多套 shadow。具体浮层数值在对应迁移中验证；v1.0 不虚构已验收的全局阴影等级。

## 4. Buttons

| 层级 | 表现 | 使用规则 |
|---|---|---|
| Primary | accent 实底 + onAccent | 当前局部最重要的下一动作；每组最多一个 |
| Secondary | Outlined，hairlineStrong 边界，accent 内容 | 普通列表执行、并列次要动作；不逐行放强填充 |
| Tertiary | 中性 TextButton / 轻量图标操作 | 规划、查看、临时事项、更多操作 |
| Destructive | error 文字/图标，必要确认场景再加强 | 仅真正删除等破坏性动作；B，不能将普通完成视作 destructive |

动作名字不决定层级：“开始”在 Home Recommendation 是 Primary，在普通列表是 Secondary；Running 的暂停是 Primary；完成并非天然 Primary。不可通过视觉优先级改变操作资格、确认要求或业务路径。

Home 已验证按钮基准：圆角 8、最小目标 48×48、水平 padding 12、垂直 8，随文字放大增高。键盘 focus 为 accent 2 描边；Filled 聚焦时用 accentSubtle 底和 accent 文字。hover 轻微、布局不变；保留 disabled、pressed、loading 的可辨认反馈，具体跨控件变体 B。

已有共享按钮的历史默认“完成 Filled”仍存在于未迁移调用处；本规范要求迁移时按场景显式选择，不在文档阶段全局改变默认值。

## 5. Lists / Rows

普通行动行的语义槽位：**leading marker → title → metadata / status → action**。不要求每行占满所有槽位；不制造空图标、重复状态或空白说明。

标题承担主体，metadata 补充时间与来源，status 用文字/小图标，操作维持稳定位置。暂停、等待、进行中尽量复用同一排列方式，避免每次状态变化都换成不同组件。允许当前状态需要更多动作时做响应式换行，仍保持标题与状态阅读顺序。

Android 至少 48 的触控目标，允许长标题和多行；窄屏先给标题空间，再把操作放下一行。Windows 以稳定横向槽位提高密度；不能因为桌面环境就默认缩小触控目标。36–40 的鼠标专用紧凑变体只有在输入模式可区分、另有触控方案并实测后采用（B），不是 v1.0 默认值。

Home 普通行动行上下各 8、组间 24，是已验证的 C 变体。其他列表可以按任务密度调整，不能无差别套用 Home 的断点或组间距。

## 6. Icons

沿用 Material 图标体系。图标表达状态或动作，不作为装饰插画、人格头像或分类大图块。小型状态图标约 16、行动图标约 18 是 Home 已使用范围；视觉尺寸不等于点击目标。

waiting 用沙漏，paused 用暂停，开始/继续用播放，完成用勾，promoted 用引用/导航语义。图标配可理解文字；图标独立按钮提供 tooltip 与辅助技术名称。不要依赖颜色或 hover 才能识别关键操作。全局图标尺寸与特殊控件的细节在迁移中验证（B）。

## 7. State Visualization

状态表达次序为 **text → icon → 少量 color**；默认不为每个状态做 chip/badge。仅当上下文不会混淆时省略重复状态文字。显示与退出条件始终由现有业务规则决定。

### PlanItem

| 状态 / 类型 | 视觉规则 | 验证状态 |
|---|---|---|
| next | 正常行动标题与执行入口；不重复标“下一步” | A：Home |
| dispatched | 在确需区分时用次级执行关联说明；不制造第二个任务或强色块 | B，保留历史业务含义 |
| done | 中性勾与次级文字，不整行绿色 | B |
| dropped | 弱化内容，保留状态说明及可用操作的正常对比度；禁止整行 .55 opacity | B |
| promoted | 引用图标 + 必要“世界节点”说明，作为导航对象；不是可执行事项 | B：呈现；Home 排除行为已验证 |

promoted 是 reference 类型语义，并非新增执行状态。遗留 draft 与 next 的兼容处理继续服从现有模型，不能为了标签统一改写存储。

### Execution

| 状态 | 视觉规则 | 验证状态 |
|---|---|---|
| pending | 正常行动标题，开始为可用动作；不虚构运行时间 | A：普通开始场景；其他行 B |
| running | 当前事项最明显，accent 家族适度强调；Home 有独立 Hero | A/C；列表变体 B |
| paused | 暂停图标 + 已暂停，中性 metadata；恢复与完成可发现 | A：Home |
| waiting | 沙漏 + 等待中，中性 metadata；不默认 warning | A：Home |
| completed | 中性勾/次级文字；按页面业务展示或退出 | B |

### Temporal

| 状态 | 视觉规则 | 验证状态 |
|---|---|---|
| inactive | 必要时显示未来推荐时间，不做执行警报 | B |
| active | 明确推荐事项和理想完成时间；Home 用主推荐层级 | A/C |
| overdue | warning 时间说明，可配小图标；不整块黄底、不误作错误 | A：Home |
| expired | 按推荐规则退出或中性说明，不将 execution 自动标完成/失败 | B：视觉；现有业务边界不变 |

Temporal 状态描述推荐窗口，不代表执行时长或执行结果。paused/waiting 的未结束执行在过期、跨日后仍需按业务保持可达。

### WorldNode

focused、notFocused、completed 的完整树呈现均为 B：关注用低强调图标/文字，不用键盘焦点描边；未关注保持正常可浏览；完成低噪声，必要时中性勾和说明，不整行失去可读性。selected 是当前 UI 选择，keyboard focus 是输入焦点，World focused 是业务关注，三者必须分别识别。

## 8. Assistant Personality

用户界面的管家名字读取 assistantName，默认 Butler；Jax 保留为项目、包名、数据库、系统 App 名称等技术身份，不引入两个并列人格。AppBar 显示当前模块名。

人格适合 Home Root 问句、Primary Recommendation 和少量有帮助的主动提醒。名字表示谁在说话，使用 body / metadata，不压过当前事项。问候低于问句或正在执行事项。

World、Planning、Settings、普通 Event 行和常规空状态使用中性直接语言。不要给每个空状态配管家发言，不增加聊天气泡、头像或无关寒暄。

## 9. Content Width

| 语义类型 | 宽度策略 | 页面映射与状态 |
|---|---|---|
| Reading / Thinking Workspace | 800–840 范围，默认 820 | Home 820：A/C；Planning 820 已迁移；Settings 820 已实施待验收 |
| Operational List | 按列信息量取 1000–1080 | Today 现有 1080、Routine 现有 1000；迁移 B |
| Full Structural View | 按结构、图表和可用窗口确定，不设虚构统一上限 | World 完整树 1040；Record 图表随事实区 1080，待验收 |

Record 明细与图表共用 Operational List 上限 1080；宽屏不单独拉宽图表。World 使用 Structural View 上限 1040。二者均为页面场景参数，不是通用上限；Record Phase D 已实施，等待真机与桌面人工验收。

maxWidth 是上限，不是最小宽度。窗口变窄时保留页边距与文字换行，不能为了对齐把内容拉得过散或造成全页横向滚动。结构视图若确需局部横向浏览，必须有明确边界与可发现操作。

## 10. Home

**C，Pilot completed；Android 第一轮整体主观验收通过。**

- **Root**：低强调问候与管家身份，问句是唯一第一层；分类是色点 + 名称的轻入口，不加数量、统计或描述卡片。无分类仍保留临时事项入口。
- **Temporal Recommendation**：事项标题是主视觉；管家引导与时间信息次级；开始为 Primary。采用连续画布，无推荐 Card。「或者做点别的」与分类入口清楚分层。
- **Running**：最高优先级，单一 accentSubtle 表面、16 圆角、无阴影；不再加分类色边框、侧标记或大状态图标。事项标题主导，计时清楚但不营销化。暂停为 Primary，其他动作保持可发现的既有菜单路径。
- **Category View**：Category → WorldNode → ancestry → 行动，分别使用 pageTitle、sectionTitle、metadata、itemTitle。规划为组级 Tertiary，空组仍保留规划路径，普通行无卡片。
- **Waiting**：中性文字与查看入口，不使用警告色或独立卡片；Category View 放在分组内容之后。长列表中的可发现性继续接受后续使用反馈。
- **ancestry**：完整名称、13 号实色 textMuted、1 线宽 hairlineStrong、每层 12、最大可视缩进 60。封顶只影响绘制，不丢失真实层级。完整 World 树不继承此紧凑缩进标准。

阅读区上限 820；手机左右 16，Windows 24；分组间 24。推荐与当前执行只保留一个视觉第一层。长名允许多行，大字号时动作下移；极长计时可保持单行并局部横向查看，此处理不是所有页面的全局溢出策略。

保留 Root → Category → Planning → Category → Root 的路径和分类滚动位置，保留推荐切换与 Running 优先行为。返回与执行逻辑不得因布局调整变化。Home 等待详情与校正时间弹窗未完整迁移，不计入已验证设计范围。

## 11. World

**B2：Android real-device validated（第一轮主观验收）。** 用户在 Phase C 启动要求中确认 World 已通过真机验收；Windows 仍仅自动验证与构建通过。实施记录见 [World Design Migration Report](world_design_migration_report.md)。

World 是长期结构地图。Category 是 section，WorldNode 是 tree node。层级通过 connector 与 indentation 表达，节点连续呈现，无逐行 Card。

关注低强调，完成低噪声；More 始终可发现，关键操作不能仅 hover 出现。浏览、业务关注、当前选择和键盘 focus 分开表达；保留原有展开、关注和管理交互。

完整树使用每层 16、默认最大可视缩进 48；可用宽度不足时，在 1–3 层可视深度间收缩，优先保留大字号标题空间。超过可视深度的行补充真实层数和完整父名，名称不截断，封顶后支线继续连接。connector 使用 hairlineStrong / 1，hover 与业务状态不改变它。普通短行最小 48，长名自然增高。

World 主树结构区上限 1040，Android / Windows 横向页边距 16 / 24；这是完整树 contextual variant，不把 Planning 820 或 Home ancestry 12/60 全局改写。分类 sectionTitle 17，节点 itemTitle 16，关注标记16，More18/点击区48；完成用中性勾+textMuted，不用删除线。主树不显示当前计划、下一步数量或 promotion 来源。Move Picker 显式启用 World 变体，头部说明和候选共用滚动区，禁用/选择资格不变。

## 12. Planning

**B1：Android real-device validated（第一轮主观验收）。** 用户在 Phase B2 启动要求中确认 Planning 真机体验没有发现明显问题；Windows 仍是自动验证与构建通过，不推定获得实机主观验收。详见 [Planning Design Migration Report](planning_design_migration_report.md)。

围绕当前 WorldNode 思考推进：**WorldNode → ancestry → PlanItems → Review**。WorldNode 是第一视觉，ancestry 是上下文，PlanItem 是连续紧凑的行动内容。

Quick Add 属于列表末尾；inline edit 轻量，编辑与保存状态清楚；promoted reference 保持导航语义；Review 低强调，必要思考空间可以更舒展。普通内容不 Card 化。

B1 已统一标题、ancestry、编辑态、Quick Add、Review、promoted 与 dropped 的表现；详情字符树线/灰色和 dropped 整行透明度已移除。具体密度、输入与双端观感仍待真机验收；本轮不修改 v1.0 token。

## 13. Today

**Phase C：migration implemented / awaiting real-device validation。** 实施与验证见 [Today + Routine Design Migration Report](today_routine_design_migration_report.md)。

围绕正在进行、现在需要处理、持续事项、稍后组织信息，分区与资格沿用当前业务。时间保留稳定位置；active / overdue 区别清楚，overdue 用 warning 文字，持续事项较轻。

paused / waiting / running 复用稳定行槽位，running 不使用分类色。completed / expired 按既有业务规则退出相应视图，不隐藏尚未结束的暂停和等待执行。Phase C 已统一纯视觉 execution shell；source-specific row 保留资格与回调。sectionTitle 17、分区间 16（compact 校准待验收），空区隐藏、不附数量。running 为 accentSubtle + 2 侧标记，计时采用紧凑 itemTitle 16 的等宽数字；暂停为 Primary，其余执行动作使用 Secondary。Later 独立时间槽；PlanItem 只显示直接 WorldNode 来源。

## 14. Routine

**Phase C：migration implemented / awaiting real-device validation。** 实施与验证见 [Today + Routine Design Migration Report](today_routine_design_migration_report.md)。

配置按实际字段组织基本信息、重复规则、时间推荐。三个时间明确命名：开始推荐、理想完成前、最晚完成前。推荐生命周期不是任务 duration，不用一条执行进度条暗示三时间之间必须持续执行。

Execution 状态与 Temporal 状态视觉分离；列表身份轻量、配置说明清楚。只能对已有功能整理分组，不借视觉迁移新增调度规则或设置。

列表复用 Today 的视觉 shell，recurrence / 按需类型作为 metadata，三时间摘要对跨午夜明确显示“次日”。排序收入 More；管理页保留原有执行能力与停用/重新启用行为。编辑弹窗按基本信息、重复规则、时间推荐分组；三个时间采用 label/value，不做三个强按钮。On-demand 不显示虚构时间字段；已有 Quick Action 值保存规则不变，不新增本页开关。

## 15. Record

**migration implemented；awaiting real-device validation。**

事实优先。真实 execution segment 是核心，chart 是摘要；主动执行 duration 与从开始到结束的 lifecycle elapsed 分开表达。暂停/等待空档不能画成连续执行。

跨日明确日期，分类颜色只用于身份图例，历史文字保持可读，不用整行低 opacity 表示“过去”。Phase D 已实施：日视图真实片段位于总时长之后、图表之前；Record 内容上限 1080，窄屏时间在标题上方，宽屏采用时间列；closed segment 不标记完成。周视图保留原有聚合，不新增周片段查询。图表标签随文字缩放；实现证据见 Phase D 报告，仍待真机验收。

## 16. Settings

**migration implemented；awaiting real-device validation。**

中性、稳定、低人格化。行遵循 label、value、description、action；可编辑性、保存结果和错误清楚。仅为真实存在的偏好设置建立 section，不提前放 theme / sync / data 等空分组，不为视觉结构新增产品功能。

管家名称是设置内容，不让管家替每一项设置发言。普通行不 Card 化，采用阅读型宽度。Phase D 保持 820 上限；只有已有名称设置，label/value/chevron 完整换行，中性编辑标题和输入 label，既有校验、保存与取消逻辑不变。

## 17. Android

- 默认横向页边距 16，交互目标至少 48×48，图标可以小于触控区域。
- 长 Category、WorldNode、行动名称自然换行；文字缩放时调整排列，不锁字号、不截掉关键动作。
- 处理窄屏、键盘弹出和输入焦点；编辑确认/取消保持原有语义，输入与按钮不被键盘遮挡。
- 遵循现有系统返回、SafeArea 与 bottom navigation，内容和底部操作可滚动到达；底部留白不能替代真实 inset 处理。
- 每次迁移检查真实中文字体、系统大字号、小屏与触摸操作。Home 用户整体认可不代替所有设备组合的验收。

## 18. Windows

- 默认横向页边距 24，按第 9 章使用语义宽度；窗口 resizing 时重新排布，不固定桌面最小内容宽度。
- 紧凑依靠稳定横排与信息槽位，不默认压缩触控目标；长名和高 DPI 下允许换行。
- row hover 使用轻量 surfaceSubtle，不改变高度、文字位置和布局。关键动作始终可发现。
- keyboard focus 使用明确 accent outline，与 hover、selected、World focused 区分。
- Tab 顺序符合阅读顺序，Enter 激活/提交遵循当前控件语义，Escape 保留当前返回/取消路径；不得用统一快捷键改写编辑行为。
- 从每个迁移阶段开始就检查鼠标、键盘、高 DPI 与 resizing，不把 Windows 留到最后 polish。

Phase D Windows polish 已实施，awaiting manual validation：沿用各页 maxWidth 和 contextual density；桌面壳使用现有 canvas / accent / hairline，保留 Microsoft YaHei UI 字体与基础权重继承。可滚动竖向列表显示轻量 scrollbar（6 宽、4 圆角）；鼠标 hover/drag 加深，Android 滚动行为不变。Windows 应用自有 dialog 外宽统一为确认 400 / 标准表单 560 / 复杂表单及 Record modal 720，受 viewport width − 80 上限约束；系统日期/时间 picker 保持 Material 自适应。Tab / Enter / Escape 遵循现有控件和路由行为，未增加业务快捷键。

## 19. Exceptions / Contextual Variants

统一的是语义和视觉语言。以下差异有明确用途：Home 可以更舒展并保留少量人格；World 可以更高密度；Planning 的思考区域允许呼吸；Today 强调时间与动作对齐；Running Hero 允许独立强调面；Modal 允许 elevation。

场景变体必须说明适用对象与验证状态，优先复用已有 token；不把单页成功经验升级为无条件全局规则。不要因“统一”给所有行加圆角、相同宽度、同样密度或相同主按钮。

World B2 场景参数：1040 结构区上限、16/48 可视缩进及窄屏大字号收缩、压缩层级的父名提示，仅作用于完整树及 World Move Picker。它们已通过 Android 第一轮主观验收，Windows 仍待实机主观验收；不改变 Home / Planning ancestry 的颜色、宽度或密度。

Phase C 列表场景参数：Today / Routine 上限 1080 / 1000；行内部可用宽度至少 880 且 16 号文字缩放后不超过 20 时使用横排，marker 24、time 108、action 344，槽间 16。窄屏与大字号改为时间在标题上方、动作在下方自动换行。计时采用 itemTitle 16 的 tabular figures，区别于 Home Hero 的 32；不改全局 typography。running 允许 accent 2 侧标记、无圆角阴影。以上为已实施、待真机验证的 Operational List 变体。

Compact Density Calibration（2026-09-17）：Today / World / Routine 使用显式 compact operational density，**awaiting real-device validation**，不扩散到 Home / Planning。Today 分区间 16、heading 下 4；execution shell 保留上下 8、title/metadata/status 间 4，窄布局 time/动作区前间距 4；行内宽至少 300 且文字缩放不超过 1.25 倍时，单动作可与内容同排，动作槽 96，实际控件仍至少 48。多动作或大字号下动作继续下移换行。Routine More 位于标题区域，三时间摘要自然换行，recurrence 到摘要 4；分类间 16。World 分类间 16，节点标题上下 4，整行与控件仍至少 48；短行不额外压缩，深度不增加纵向间距。标准 shared default 不变；颜色、字体、图标、按钮主次与业务行为不变。详见 [Density Calibration Report](compact_density_calibration_report.md)。

Phase D 场景参数（implemented，awaiting validation）：Record 行上下 8、内容间 4、分区 16；内宽至少 720 且 16 号字缩放后不超过 20 时采用 224 时间列、16 槽间距，否则纵排。时间采用 body 14 与 tabular figures，duration/source 使用 metadata 13，标题 itemTitle 16，sectionTitle 17，pageTitle 26。分类图标签使用 metadata 13 而非另造小字号。24 小时图依真实比例绘制，短片段命中区沿用最小宽 32、高 28/34（文字放大时行高增加）；这是精细图形 contextual exception，不能将比例图全部扩成 48 而相互覆盖，同页事实列表提供至少 48 高的完整编辑入口。三档 Windows modal 宽度只作用于桌面；Android 已迁移页面约束为 null，沿用原布局。

新参数经真实页面验证后更新本文件和 Validation Status，必要时发布 1.1、1.2。记录修改原因、影响范围、双端验证和未解决限制；不每轮重新引入另一套品牌风格。仅文档规范更新不隐含代码迁移授权。

## 20. Do / Don't

| Do | Don't |
|---|---|
| 内容优先，字号与间距建立层级 | 每行 Card、每状态 Chip |
| 同语义一致，按场景决定主动作 | 永远“完成 Filled”、列表每行强主按钮 |
| 分类与执行状态各自表达 | 分类色充当 running / waiting / overdue 色 |
| 固定语义文字色与足够触控区域 | 用 11 号小字、大量 opacity 换密度 |
| 稳定 title / metadata / action 槽位 | 每换状态就换整套行组件 |
| 克制强调，无普通内容阴影 | 营销大标题、彩色卡片墙、阴影泛滥 |
| 人格集中于 Home 和必要主动建议 | 所有页面都让管家说话 |
| 保留业务与真实记录 | 为了 UI 重写生命周期、去重、Sync 或计时 |
| Android / Windows 同阶段验证 | 只看默认截图，最后才处理 Windows |
| 根据任务选择密度与宽度 | 为统一让所有页面完全相同 |

## 21. Design References

历史灵感包括 Linear 的精确结构与克制强调、Notion 的内容优先和思考空间、Cal.com 的时间清晰与动作层级、Intercom 的温和主动表达。这些已转化为 Jax 自己的规则，不是按页面分配品牌风格。

审计时阅读的是 VoltAgent / awesome-design-md 中对应的第三方 DESIGN.md 分析，主要取材于品牌官网，**不是官方产品组件规范**。本轮没有重新阅读或据此重新设计。后续 UI 工作只需先读本文件，不要求重复访问外部参考；不复制其品牌色、营销标题、阴影、展示卡片或聊天界面。

## 22. Validation Status

| 页面 / 范围 | 状态 | 证据与限制 |
|---|---|---|
| Home 主内容四态 | Pilot completed；Android 真机体验已通过第一轮主观验收 | 用户确认整体可以接受、可沿此方向推进；不是每个 checklist 已逐项签收 |
| Home Windows | 自动测试、离屏检查与构建完成 | 未收到 Windows 实机主观验收；高 DPI/长时使用继续验证 |
| World | Android real-device validated（第一轮主观验收） | 用户在 Phase C 启动时确认；Windows 实机主观验收仍未收到 |
| Planning | Android real-device validated（第一轮主观验收） | 用户于 B2 启动时确认无明显问题；Windows 实机主观验收仍未收到 |
| Today | migration implemented；awaiting real-device validation | Phase C 四分区、统一执行行、时间槽与按钮主次已实施；自动验证见迁移报告 |
| Routine | migration implemented；awaiting real-device validation | Phase C 列表、More 排序、编辑分组、跨午夜说明已实施；待 Android / Windows 实机体验 |
| Record | migration implemented；awaiting real-device validation | 真实片段优先、跨日日期、主动时长、响应式时间列与图表；自动证据见 Phase D 报告 |
| Settings | migration implemented；awaiting real-device validation | 中性名称设置、完整 value、就近错误和现有保存/取消；待真机体验 |
| Windows 全局 polish | polish implemented；awaiting manual validation | 语义宽度、既有密度、hover/focus、三档 dialog、scrollbar 与 resize；Android 已验收页面保持原行为 |
| Android 全局壳及历史辅助页面 | 本轮保持既有实现 | Phase D 不重做 Home / Planning / World / Today / Routine 的 Android 布局 |
| Design System migration | Phase D implementation complete；awaiting user validation | 不标记 completed / validated；等待用户确认后再收口 |
| B 类 token / 变体 | 已定义基线，待对应页面验证 | caption、success/error、32 spacing、4 radius、独立白表面、divider/input/elevation 等 |
| Today / World / Routine compact density | implemented；awaiting real-device validation | 真机反馈驱动的局部密度校准；既有迁移验收不代表本次密度已验收 |
| Dark mode | Not yet defined | 不由浅色自动推导 |

Home 自动验证记录：68 项相关测试通过、静态检查无问题、Android debug / Windows release 构建成功；布局矩阵含两端 1× / 2× 字号、长名、空状态、深 ancestry、暂停/等待与 promoted 排除。离屏使用本机 QA 中文字体，不能替代 Android 字体或设备屏幕验收。Android 已覆盖安装，用户随后给出本轮整体认可。上述均为既有 Pilot 证据，本次文档固化没有重新构建、测试或安装应用。

### Audit Candidate → Home Pilot Actual → v1.0 决策

| 主题 | Audit 候选 | Pilot 最终实际 | v1.0 处理 |
|---|---|---|---|
| 主要颜色 | 第 3 章所列浅色候选 | 色值保留；按背景调整文字角色 | A 采用实际用途，未使用角色单列 B |
| 标题 / metadata | 26 / 17 / 16 / 14 / 13 | 相同；metadata 取消低透明度 | 采用；caption 12 仍 B |
| ancestry 旧实现 | 已发现 11 + 透明度风险，建议 13 | 13 实色，strong connector | Home C 已验证；不是全局树缩进 |
| spacing | 4/8/12/16/24/32/48 | 主要 4/8/12/16/24/48，局部 1 光学校正 | 32 保留 B，不宣称已验证 |
| radius | 4/8/16 | 按钮 8、Hero 16、普通行无容器 | small 4 保留 B，large 仅指定场景 |
| 推荐容器 | 无 Card 或轻 surface 均可 | 无 surface、Filled 开始 | Home 固化无 surface；其他推荐表面 B |
| Running | 可选淡底、2 侧标记 | 仅淡底、无侧标记；次级深字 | 不强制侧标记；紧凑列表 marker B |
| Windows 密度 | 鼠标可 36–40 | 48 目标，两端按布局调密度 | 48 为默认；小目标不是通用规则 |
| 分组线 | 留白或 hairline | Home 仅留白；边框与树线单独配置 | 不把未画的 divider 认作实测 |

### 阶段推进记录与版本迭代

Phase B 当时采用 **Planning first → World** 的推进顺序：Planning 与 Home 共享 WorldNode 上下文、ancestry 和行动语义，可先验证概览/详情、编辑与 Review，再处理完整树的密度和交互分区。不要同时改两页及全局 Theme，使偏差难以定位。

当前已完成 Phase D 实施，停止继续扩散 UI 迁移并等待人工验收。Windows 实机观感和 B 类参数仍作为验收任务，而非假定已经通过。只有用户确认后，才更新 completed / validated 状态；后续根据实际验收修订版本并在本章记录证据。

Phase D 实施与验收入口：[Phase D Migration Report](phase_d_design_migration_report.md)。本轮完成后暂停迁移，不进入开源清理或发布。
