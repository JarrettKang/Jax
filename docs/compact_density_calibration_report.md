# Today / World / Routine Density Calibration Report

## 修改前只读审计

以 DESIGN.md 为准。本轮只调整三页密度，不改变颜色、字体、图标、按钮主次、信息分区或业务。下面 A=触控需要，B=视觉留白，C=历史遗留，D=共享组件额外高度，E=可安全压缩。

| 页面 / 位置 | 高度来源 | 分类与决策 |
|---|---|---|
| Today / Routine execution shell | 上下各8、title→metadata4、metadata→status4 | B；内文已紧凑，保留，不靠缩字 |
| shell 手机动作 | 内容后8 + 至少48动作；即使只有一个开始或一个More也换行 | A+D+E；保留48目标，允许单动作在有足够文字宽度时同排，Routine More 移入标题区域 |
| shell 时间 | 手机 time 后8 | B+E；压至4，时间内容不变 |
| shell 多动作 | Wrap spacing/runSpacing8，换行增加48 | A+B；保留按钮与Wrap8，只缩动作区前间距8→4 |
| Today sections | section间24、heading下8；行间无另加gap/Divider | B+E；section16、heading4；保留四区及空区资格 |
| World Category | minHeight48；标题上下8；section底24 | A+B+E；48与标题padding保留，section降16 |
| WorldNode | main/leading/More至少48；标题上下8；无sibling/parent-child额外gap | A+B+E；短行不低于48；长行标题上下4，减少多行高度；connector跟随真实行高 |
| Routine Category | header由48按钮决定；section底24 | A+B+E；header保留，section底16 |
| Routine metadata | recurrence与三时间摘要直接相接，无额外gap | B；补4保证紧凑后仍可分辨，不压缩文字或省略时间 |
| Routine editor | 组间24、字段16 | B；配置表单并非本轮行密度来源，保持原样 |
| ListTile / ExpansionTile | 三页主列表未使用ListTile；停用组使用ExpansionTile | 非主要来源；不改全局ListTile visualDensity |
| SafeArea / bottom navigation | App壳负责；页面底部48、顶部16 | A/B；保留系统inset与底部留白，不从导航可达区域挤空间 |
| Shared defaults | shell被Today/Routine使用；paused/waiting还有Home默认分支；World浏览row有显式参数 | D；密度采用默认standard的显式compact参数，Home/Planning/Picker不自动继承 |

没有发现旧字号导致高度异常；不修改Typography。World已没有大段sibling gap，不能承诺所有短节点都显著缩短，改善集中于多行节点和分类间距。

## 实施结果

状态：**implemented / awaiting real-device validation**。本轮是密度校准，未重做设计语言。用户此前确认的 World 迁移验收不代替本次 compact 密度验收。

| 调整点 | 修改前 → 修改后 | 保护边界 |
|---|---|---|
| Today section gap | 24 → 16 | 四区、排序、空区资格不变 |
| Today heading 下方 | 8 → 4 | sectionTitle 17 不变 |
| execution row 时间/动作区前 gap | 8 → 4（compact窄布局） | 时间文字与动作保留 |
| execution row 内 padding | 上下8保持 | 标题→metadata4、metadata→status4保持 |
| Today 单动作 | 手机统一独立动作行 → 行内宽≥300、文字缩放≤1.25时同排 | 动作槽96；控件目标≥48；大字或多动作仍自然换行 |
| Routine More | 手机单独占用动作行 → 标题区域右侧 | More目标48，菜单与回调原样；宽屏沿用既有动作列 |
| Routine On-demand | 同样采用compact单动作排列 | 大字号继续将开始/继续下移，More留在标题区域 |
| Routine recurrence→time summary | 0 → 4 | 补足两种metadata的呼吸空间；全文自然换行，不ellipsis、不缩字 |
| Routine Category gap | 24 → 16 | 分类标题、折叠和排序不变 |
| World Category gap | 24 → 16 | 分类标题上下8、展开/Add/More的48目标不变 |
| WorldNode title padding | 上下8 → 4（compact） | 行/leading/More仍≥48，多行节点自然增高，缩进与connector样式不变 |
| ListTile / visualDensity | 无全局调整 | 三页主行不是ListTile；停用ExpansionTile、编辑表单、SafeArea、导航壳保持原状 |
| minHeight / button height | 不修改48下限 | 不采用30dp节点或36dp鼠标专用按钮，不改按钮Filled/Outlined主次 |

### 文件与共享组件

生产改动仅八个 UI 文件：

- `lib/ui/theme/list_density.dart`：新增 `JaxListDensity.standard / compact`。
- `lib/ui/widgets/execution_row_shell.dart`：默认 standard；compact 控制时间/动作 gap、单动作同排；可选 trailing 槽供 Routine More 使用，无实体/业务分支。
- `lib/ui/widgets/world_node_browsing_row.dart`：默认 standard；compact 仅将标题上下padding设4。
- `lib/ui/pages/events_page.dart`：显式compact及section间距。
- `lib/ui/pages/routine_page.dart`：显式compact、More槽、metadata与分类间距。
- `lib/ui/pages/world_page.dart`：主树显式compact、分类间距；Picker不继承。
- `lib/ui/widgets/paused_routine_row.dart`、`waiting_routine_row.dart`：既有Today opt-in视觉分支使用compact；默认Home分支不变。

新增 `test/ui/compact_density_test.dart` 记录实际三页的视口信息量，验证行及控件≥48、手机Routine More在行顶部8位置。既有 Today/Routine/World 视觉测试与业务回归保留，未修改业务断言。

Home / Planning 页面、theme及其默认共享行路径保持原样；Record / Settings不变；Core/Data/Sync/controller不变。按钮文字、颜色、图标、字号、圆角、排序和所有业务回调保持原样。

`docs/DESIGN.md` §13、§19、§22 已补充页面限定密度规则和待真机验收状态，未把compact升级为全局默认。

## 同视口修改前后对比

固定测试数据、微软雅黑QA字体、1×字号、390×844 logical px。顶部栏与底部导航占用后，列表视口为708；只统计**完整可见的条目行**，不计被底部裁掉的行。World统计Node，不把Category混入节点数量。

| 页面 / 测试场景 | 修改前完整可见 | 修改后完整可见 | 首条行高前→后 |
|---|---:|---:|---:|
| Today：4条active + 多条persistent PlanItem | 4 | 7 | 118 → 64 |
| Routine：三时间Scheduled / 无时间Scheduled / On-demand循环 | 4 | 7 | 156 → 104 |
| World：多分类、短名/两行名称交替、含focused/completed | 9 | 10 | 62 → 54 |

360与430宽下这三组完整可见数同样为4→7、4→7、9→10；具体行高随换行变化。上述是固定fixture的对比，不代表所有真实数据必然提升同样比例。Today多动作、长名和大字行仍保留较多高度；World短行原本48，保持不变，没有强行追求数量提升。

前后截图及JSON：`build/density-qa/before/`、`build/density-qa/after/`。例：

- [Today 修改前](../build/density-qa/before/today-android-390-1.0.png) / [修改后](../build/density-qa/after/today-android-390-1.0.png)
- [Routine 修改前](../build/density-qa/before/routine-android-390-1.0.png) / [修改后](../build/density-qa/after/routine-android-390-1.0.png)
- [World 修改前](../build/density-qa/before/world-android-390-1.0.png) / [修改后](../build/density-qa/after/world-android-390-1.0.png)

## Android / Windows 验证范围

新增30组：Android360/390/430、Windows480/1400 × 1×/2×字号 × 三页，包含顶部栏、底部导航、三时间换行和48目标检查。既有48组执行/编辑矩阵覆盖running Event/Routine、paused/waiting、多persistent、长中文、多个动作、无时间与跨午夜。既有24组World矩阵覆盖多分类、siblings、3至9层、长名、focused/completed、展开与More。

合计102组视觉测试通过。代表截图已人工检查：390默认三页、360/2×Routine、390 running/paused/waiting和多动作、390深树及320/2×深树。未见文字碰撞或布局overflow；连接线随实际行高衔接，没有通过缩进之外的额外纵向间距区分层级。

Windows沿用相同compact规则，宽窗口原有横向槽位保持；窄窗/大字回退换行。没有另行缩小Windows按钮目标，避免同一窗口的触摸可达性变化。hover/focus与输入行为保留既有实现。

## Compact Density 真机验收 Checklist

1. Today：一屏是否明显能看到更多事项。
2. Today：相邻行是否仍容易分辨。
3. Today：开始 / 继续 / 完成是否仍好点。
4. Today：四个section是否仍清楚。
5. World：Category是否不再占过多空间。
6. World：sibling是否更紧凑。
7. World：parent / child是否仍清楚。
8. World：6+层树、长名与connector是否舒服。
9. World：More是否仍好点，展开/关注是否容易区分。
10. Routine：一屏Routine数量是否提升。
11. Routine：title / recurrence / time是否仍清楚。
12. Routine：多行time summary是否自然。
13. Routine：More是否与标题区域合理对齐。
14. Routine：不带时间的行是否没有多余空白。
15. 整体：是否compact而非拥挤；默认/大字号、滚动、按钮与底部导航是否舒服。

以上全部待用户验收。特别关注同排单动作使标题可用宽度减少后，真实长名称是否需要更多空间；2×字号优先可读性，不保证提升同样信息量。离屏QA字体不代表Android设备字体与真实触摸手感。本轮完成后停在密度校准，不进入Record/Settings，也不自动安装或标记validated。

## 最终自动验证结果

2026-09-17，最终代码完成后：

| 检查 | 结果 | 记录 |
|---|---|---|
| flutter analyze | No issues found | `build/density-analyze.log` |
| flutter test（全量，含Home/Planning/World/Today/Routine与Core/Data/Sync） | 656 passed | `build/density-full-tests-final.log` |
| 中文视觉矩阵 | 102 passed（包含于全量测试，不重复计数） | `build/density-visual.log` |
| Android debug build | 成功 | `build/density-android-build.log` |
| Windows release build | 成功 | `build/density-windows-build.log` |
| 修改范围hash核对 | 通过；保护的生产文件未变，无基线文件删除 | `build/density-before.json`、`build/density-changed-files.txt` |

Android仅有既有Gradle/native-access工具链提示；测试无失败或命中区域警告。产物：`build/app/outputs/flutter-apk/app-debug.apk`、`build/windows/x64/runner/Release/jax.exe`。本轮未安装、未启动生产应用、未提交Git，保留工作区既有修改。

## 真机覆盖安装记录

Private device rollout evidence omitted from this historical version.

