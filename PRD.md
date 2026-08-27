# Jax 电子管家产品需求文档

## 1. 文档信息

- 产品名称：Jax（我的电子管家）
- 当前版本：v0.2（F2：事件层级）
- 目标平台：Windows、Android
- 文档状态：需求已确认，作为后续开发基线
- 更新日期：2026-08-25

## 2. 产品目标

Jax 是一款用于管理和记录个人生活的软件。最终目标是实现 Windows 与 Android 双端使用和数据同步。

v0.1 的目标是在 Codex 工作区内完成一个仅支持 Windows 的最小可运行版本，用最少但完整的功能验证事件创建、执行计时、完成归档和本地持久化这条核心业务链路。

本版本遵循 Local First 原则：软件在没有服务器或网络的情况下仍须完整可用。服务器在未来主要承担设备间同步职责，而不是本地功能运行的前提。

## 3. 开发原则

### 3.1 三层架构

每次新增功能均须按以下三层组织：

- Core（业务层）：保存状态转换、计时、校验和业务约束等统一规则。
- Data（数据层）：保存数据模型、本地数据库和持久化逻辑。
- UI（界面层）：负责用户交互和展示，不自行定义业务规则。

未来 Windows 与 Android 端必须遵循同一套 Core 业务规则和 Data 数据模型。两端 UI 可以不同，但最终功能和行为必须一致。

### 3.2 小步迭代

- 每个开发版本或增量只增加一个能够独立验证的行为变化。
- 新增行为前，先更新统一需求、数据模型和测试规则。
- 新增行为后，已有测试必须继续通过。
- 第三阶段开始新增核心功能时，须先完成 Windows 端，再完成 Android 端；只有两端均通过统一测试，该功能才算完成。

### 3.3 本地优先

- v0.1 的全部数据保存在本地。
- v0.1 不依赖网络、账号或服务器。
- 数据模型需要为未来设备同步保留稳定的唯一标识和扩展空间。

## 4. 产品路线

1. 在 Codex 中完成 Windows 端最小可运行版本。
2. 仿照 Windows 端最小版本，实现仅支持 Android 的手机端最小版本。
3. 继续添加核心功能：先更新统一需求、数据模型和测试规则，再分别实现 Windows 与 Android 端。
4. 租用服务器，实现 Windows 与 Android 之间的数据同步。

## 5. v0.1 功能范围

### 5.1 事件系统

事件系统展示所有尚未完成的一次性事件，包括 `pending`、`running` 和 `paused` 状态的事件。已完成事件不再显示于事件系统。

#### 5.1.1 事件属性

每个事件至少包含：

- ID：由程序生成的全局唯一标识，界面不显示，为未来同步使用。
- 名称：用户输入的事件名称。
- 状态：`pending`、`running`、`paused` 或 `completed`。

#### 5.1.2 名称规则

- 事件名称不能为空。
- 允许创建多个同名事件。
- 系统通过 ID 而非名称区分事件。

#### 5.1.3 状态含义

- `pending`：未开始。
- `running`：正在执行并计时。
- `paused`：已经开始但当前暂停，暂停期间不计时。
- `completed`：已经完成，并已进入记录系统。

#### 5.1.4 各状态允许的操作

| 当前状态 | 编辑 | 删除 | 开始/恢复 | 暂停 | 完成 |
| --- | --- | --- | --- | --- | --- |
| `pending` | 允许 | 允许 | 允许开始 | 不适用 | 不允许 |
| `running` | 不允许 | 不允许 | 不适用 | 允许 | 允许 |
| `paused` | 允许 | 允许 | 允许恢复 | 不适用 | 不允许 |
| `completed` | 不在事件系统操作 | 不在事件系统操作 | 不允许 | 不允许 | 不适用 |

删除未完成事件时，该事件和尚未完成的执行过程一并删除，不生成历史记录。

### 5.2 执行系统

#### 5.2.1 状态转换

- 开始事件：`pending → running`
- 暂停事件：`running → paused`
- 恢复事件：`paused → running`
- 完成事件：`running → completed`

除上述转换外，v0.1 不允许其他状态直接转换。

#### 5.2.2 单一运行约束

- 任意时刻最多只能有一个事件处于 `running` 状态。
- 可以同时存在多个 `paused` 事件。
- 已有事件处于 `running` 状态时，如果用户尝试开始一个 `pending` 事件或恢复一个 `paused` 事件，系统必须阻止该操作，并提示用户先暂停或完成当前事件。
- 系统不得自动暂停当前事件来切换任务。

#### 5.2.3 计时规则

- 事件首次从 `pending` 进入 `running` 时，使用设备当前系统时间记录开始时间。
- `running` 期间计入实际持续时间。
- `paused` 期间不计入实际持续时间。
- 事件可以多次暂停和恢复，最终持续时间为所有实际运行时段之和。
- 事件从 `running` 进入 `completed` 时，使用设备当前系统时间记录结束时间。
- 系统根据执行过程计算实际持续时间，不能由 UI 自行计算或由用户手动填写。

#### 5.2.4 软件关闭行为

- 正常关闭 Jax 时，如果存在 `running` 事件，系统自动将其转换为 `paused`。
- 自动暂停的时间点作为该运行时段的结束点。
- 软件关闭期间不计入持续时间。
- 下次打开 Jax 后，该事件保持 `paused`，由用户决定是否恢复。
- v0.1 不承诺在断电、系统崩溃或强制结束进程等异常退出情况下实现绝对精确的计时恢复；正常关闭必须正确处理。

### 5.3 记录系统

#### 5.3.1 完成归档

- 一次性事件完成后，从事件系统的未完成列表中消失。
- 完成事件作为一条完整的历史执行记录进入记录系统。
- 完成归档不能导致事件身份丢失，历史记录继续使用原事件 ID。

#### 5.3.2 历史记录内容

每条历史记录至少包含：

- 事件 ID
- 事件名称
- 状态 `completed`
- 开始时间
- 结束时间
- 实际持续时间

#### 5.3.3 时间存储与显示

- Data 层保存完整时间戳。
- UI 层根据用户当前本地时区显示时间。
- 内部时间数据不得只保存格式化后的界面文本。

#### 5.3.4 历史记录操作

- 用户可以查看历史执行记录。
- 用户可以删除某一条历史记录。
- 删除历史记录时，同时删除该已完成事件及其执行记录。
- v0.1 不支持编辑已完成的历史记录。

### 5.4 保存系统

#### 5.4.1 自动保存

- 所有改变业务数据的操作完成后，系统自动将最新数据写入本地存储。
- 重新启动软件后，尚未完成的事件和历史记录仍然存在。
- 自动保存为全局能力，不由各个 UI 页面分别定义不同的保存规则。

#### 5.4.2 手动保存

- 软件提供全局手动保存操作。
- 手动保存会立即强制把当前数据写入与自动保存相同的本地存储。
- 手动保存不是“另存为”或导出备份。
- 手动保存不建立独立于自动保存的数据机制；SQLite 自动持久化仍是主要保存机制。
- 操作后必须向用户明确显示保存成功或失败。

#### 5.4.3 保存状态反馈

- Jax 全局显示最近一次成功持久化到本地数据库的本地时间，例如 `最后保存：21:18:32`。
- 自动保存成功或手动保存/flush 成功后更新“最后保存时间”；该时间代表真正完成持久化的时刻，而不是点击保存按钮的时刻。
- 保存失败时不得更新时间，继续显示上一次成功保存的时间；保存过程中可以显示“正在保存……”等临时状态。
- “最后保存时间”仅为运行期间的 UI 状态，不为显示该时间额外写入数据库。

## 6. 建议技术基线

为支持当前 Windows 端以及后续 Android 端共享业务规则和数据模型，暂定：

- 应用框架：Flutter / Dart
- 本地存储：SQLite
- 唯一标识：UUID
- 时间规则：Data 层保存完整时间戳，Core 层负责时间计算，UI 层负责本地化展示

技术实现可以在创建项目时进一步验证，但任何调整都不能破坏三层架构、Local First 原则或未来 Windows/Android 共用核心规则和数据模型的要求。

## 7. v0.1 验收条件

v0.1 至少需要通过以下行为验证：

1. 可以创建名称非空的事件，并自动生成不显示在 UI 中的唯一 ID。
2. 可以创建多个同名事件，且它们拥有不同 ID。
3. 可以编辑和删除 `pending` 事件。
4. 可以开始 `pending` 事件并进行计时。
5. 同一时间不能开始或恢复第二个事件。
6. 可以暂停 `running` 事件，且暂停期间不计时。
7. 可以编辑和删除 `paused` 事件。
8. 可以恢复 `paused` 事件，并累计暂停前后的实际运行时长。
9. 可以完成 `running` 事件，事件随后从事件系统消失并进入记录系统。
10. 历史记录正确保存开始时间、结束时间和扣除暂停时间后的实际持续时间。
11. 可以查看和删除历史记录。
12. 每次数据变更能够自动保存，重启软件后数据仍然存在。
13. 手动保存能够强制写入数据，并显示明确结果。
    - 自动保存成功和手动保存成功后均正确更新最后保存时间；保存失败时不得错误更新。
14. 正常关闭软件时，`running` 事件自动暂停；再次打开后保持 `paused`，关闭期间不计时。
15. 新增每项行为后，之前已经通过的测试仍然通过。

## 8. Android v0.1 平台规则与验收

- Android 与 Windows 共用 Core 业务规则、Data 数据模型和 Repository 语义；Android application ID 为 `com.example.jax`。
- Android 切换后台、锁屏、返回键离开主页面、返回桌面或被系统正常回收进程时，不得自动暂停 `running` 事件。只有用户明确点击“暂停”或“完成”才改变其运行状态。
- 进程重新启动后，从本地数据库恢复 `running` 状态和未结束执行片段，并根据真实时间戳继续计算持续时间；不依赖 UI、后台 Service 或后台逐秒任务持续运行。
- Windows 正常关闭窗口时自动暂停仍是 Windows 专属生命周期策略，不映射到 Android。
- Android 优先复用现有 Flutter UI，仅进行手机正常使用所需的最小响应式和触控适配：不得明显 overflow，重要文字和操作不得被截断，必要内容可滚动，对话框和返回行为合理，主要操作可触控；不得复制 Android 专用业务页面。
- Android v0.1 验收必须覆盖实际 Android SQLite 持久化、进程恢复、上述生命周期行为以及完整核心业务流程，同时确认 Windows 行为无回归。

## 9. v0.2 F1：首页

- Jax 在 Windows 和 Android 的导航中均按“首页 / 事件 / 记录”排列，并默认从首页启动；两端共用首页内容和业务规则，仅导航外壳可响应屏幕宽度变化。
- 首页顶部按设备当前本地时间显示“早上好，我是 Jax”“上午好，我是 Jax”“中午好，我是 Jax”“下午好，我是 Jax”或“晚上好，我是 Jax”。时间区间为：`05:00 <= time < 09:00` 早上、`09:00 <= time < 11:00` 上午、`11:00 <= time < 14:00` 中午、`14:00 <= time < 17:00` 下午，其余时间为晚上。问候语在进入、返回首页及跨越区间边界后按当前时间刷新，不作为业务数据持久化。
- 当前没有 `running` 事件时，首页显示可点击的“我们来做点什么？”；点击后只切换至事件栏目，不创建或开始事件。
- 当前存在 `running` 事件时，首页以工作上下文卡片展示正在推进的主体及步骤状态，不提供暂停、完成或其他快捷操作。running Event 有直接上层时以该上层为工作主体，并按任意深度显示主体的祖先路径；running Event 为顶级时以自身为主体。
- 工作上下文中的步骤取自工作主体的直接下层并严格遵循既有同级顺序，以清晰但不改变业务的视觉状态区分 `completed`、`running`、`paused` 与 `pending`；顶级 running Event 以自身作为唯一当前步骤。running 步骤显示既有直接运行计时。
- 步骤较多时首页只显示包含 running Event 的邻近有序窗口，并提示前后存在省略内容；不得用百分比、完成比例或状态重排暗示强制工作流。
- 首页只读取现有事件系统的 `running` 状态，不维护或持久化独立的当前任务数据，不改变现有 SQLite schema。

F1 验收须覆盖上述问候时间边界、两种首页状态、事件开始/暂停/恢复/完成后的同步、Windows 与 Android 的三项响应式导航、重启恢复后的首页状态，并确认 v0.1 行为无回归。

## 10. v0.2 F2：事件层级

### 10.1 层级模型与编辑

- 没有直接上层事件的 Event 是顶级事件；每个 Event 最多一个直接上层事件，可以有多个直接下层事件，层级深度不限且始终必须无环。
- 层级只保存当前 Event 的直接上层事件 ID；下层事件由该关系查询，不保存重复列表。设置新上层或添加下层均表示移动已有 Event，不复制或新建 Event；解除关系只使下层成为顶级事件，不删除 Event、run_segments 或历史事实。
- 事件和记录中的 Event 均可查看、设置、移动和解除上下层关系。未完成 Event 的上层候选只能是未完成 Event、下层候选可以是任意 Event；completed Event 的上层候选可以是任意 Event、下层候选只能是 completed Event。候选必须排除自身、后代和其他会形成非法关系的 Event。
- completed Event 仍是原 Event，调整层级只改变时间向哪些上层聚合，不修改其执行时间事实。

### 10.2 执行与状态

- 全局仍最多只有一个 `running` Event。当前 running Event 切换到其直接或间接下层 Event 时，系统自动暂停当前 Event、关闭开放片段并开始或恢复该下层；切换到上层、同级或无关 Event 仍须先手动暂停或完成。
- 下层 Event running 时，路径上所有未完成上层 Event 均为 `paused`；此前为 pending 的上层也转为 paused。`paused` 表示事件已经开始推进但当前没有直接执行。下层完成后不自动恢复上层。
- 有任何未完成直接下层时不得完成上层。至少有一个直接下层且全部直接下层均 completed 时，pending 或 paused 上层可以直接 completed；从未直接执行的上层不伪造开始时间，直接执行时间为零。没有下层的普通 Event 保持原状态规则。
- 任何拥有直接下层的 Event 均不得删除；必须先解除或移动下层关系。没有下层时沿用原状态对应的删除规则，删除自身不删除其上层。

### 10.3 时间统计与展示

- 直接执行时间是 Event 自己全部 run_segments 之和。总投入时间是该 Event 及所有后代 Event 的直接执行时间之和，不对已聚合的总投入再次求和。
- 首页从现有层级关系推导 running Event 的工作主体和任意深度祖先路径，并从现有有序同级查询展示主体下的真实步骤状态；不持久化第二份 hierarchy、ordering 或进度数据。
- 记录首页显示 completed Event 中上层为空或上层尚未 completed 的最高已完成节点。记录详情显示总投入、直接执行时间、直接下层及其总投入，并支持逐层进入任意深度。

### 10.4 旧数据兼容

- v0.1/F1 旧数据库升级后，所有既有 Event 默认成为顶级事件；ID、状态、时间戳、run_segments、直接执行时间和历史记录必须完整保留。Windows 与 Android 共用同一 schema 和 migration，禁止通过删除数据库或清除数据完成升级。

F2 验收须覆盖任意深度、无环、移动与解除、候选范围、层级执行状态、完成与删除约束、直接/总投入时间、首页与记录展示、真实旧 schema migration 以及 Windows/Android 全部历史回归。

### 10.5 v0.2 F3：同级事件排序

- 拥有相同直接上层的 Event 构成一个有序同级集合；没有上层的顶级 Event 也使用同一排序规则。
- 顺序表示用户计划推进顺序，与 Event ID、层级、状态、创建/完成时间、执行时间和优先级独立；状态变化和实际执行顺序不改变用户定义顺序，也不强制前置条件。
- 用户可以在同级集合内手动重排序；排序不能直接改变上层关系。completed Event 也可排序，排序不改变任何执行记录或时间事实。
- 新建 Event、移动到新上层或解除上层关系时，进入目标同级集合末尾；删除 Event 后其余 Event 保持相对顺序。
- 事件、世界和首页按同级排序展示；首页继续读取真实 Event 状态，不维护独立步骤数据。

### 10.6 v0.2 F4：恢复已完成事件

- completed Event 可以从世界页的更多菜单执行“恢复事件”，恢复后状态为 `paused` 并重新进入事件栏目；恢复不自动开始计时、不抢占或改变当前 running Event。
- 恢复保留 Event ID、既有 run_segments、直接与聚合时间事实、层级关系和同级顺序；取消当前完成结论，完成时间随之清除。
- 恢复 Event 时，其向上的连续 completed 祖先同步恢复为 `paused`，直到没有上层或遇到本来未完成的祖先，避免 completed 上层包含未完成下层。
- 恢复只向上维护一致性，不自动恢复 completed 下层；恢复后再次完成仍遵守既有下层完成约束。

### 10.7 v0.2 F5：等待中事件

- `waiting` 表示 Event 仍在推进、但正等待外部过程或结果；`paused` 表示用户主动中断且当前未继续推进，两者是不同产品状态。
- 全局仍最多一个 `running`，但可同时存在多个 `waiting`。waiting 不创建等待片段、不累计 direct duration，也不改变 aggregate duration 的既有定义。
- 支持 `running → waiting`、`paused → waiting`、`waiting → running`、`waiting → paused` 和 `waiting → completed`。进入 waiting 时关闭已打开的 running segment，恢复为 running 时创建新 segment 并沿用单 running 冲突规则。
- waiting 属于未完成状态，completed 上层不得包含 waiting 下层；waiting 不向上层或下层自动传播。completed Event 的恢复仍回到 `paused`。
- 首页以“当前正在做”保留既有完整 running 上下文，并以次级的“同时在等待”列表展示所有 waiting Event 及简洁祖先路径；列表沿用现有 hierarchy/sibling 稳定顺序。

### 10.8 v0.2 F6：世界结构视图

- 新增“世界”主栏目，与“今日”和“记录”职责区分；第一层按用户顺序展示 Category 总览，进入某个 Category 后，第二层展示该分区全部 pending、paused、running、waiting、completed Event 的完整结构。
- Category 总览以响应式卡片展示 Event 总数、顶级 Event 数量，并对包含唯一 running Event 的 Category 作轻量强调；这些信息从当前 hierarchy 实时派生，不持久化为统计事实。
- Category detail 直接复用现有 hierarchy 与 sibling ordering 构造树状视图；completed Event 只改变 status，不从树中移走、不自动沉底、不打散层级或历史事实。
- 有下层的 Event 节点支持 World detail session 内展开/折叠，不新增 Event 数据库字段。状态图标沿用今日和首页的状态视觉语言。
- 世界以结构浏览为主，操作为辅；层级详情、上移、下移、编辑继续调用既有 Core/UI 业务入口，不能绕过层级、排序、删除和单 running 约束。

### 10.9 v0.2 F6.1：世界结构状态

- 世界同时保留 Event 的真实 status 与仅用于展示的结构状态；真实 status 不向祖先传播，唯一 running、direct/aggregate duration、run_segments 和生命周期规则不变。
- Event 自己为 running 时世界显示“正在执行”；否则任意深度后代存在 running 时显示“推进中”。没有 running 但自己或后代存在 waiting 时显示“等待中”；其余显示真实的 paused、pending 或 completed 语义。
- 结构状态由当前 hierarchy 与真实 status 实时派生，不持久化、不产生迁移、不修改 Event 状态，也不因展开/折叠改变。running 后代优先于 waiting 后代，completed hierarchy 约束继续由 Core 保证。

### 10.10 v0.2 F6.2：世界分类

- Category 是独立于 Event hierarchy 的一级世界分区；只有顶级 Event 直接拥有一个 nullable Category，所有 descendants 通过当前顶级祖先继承分类。
- 系统提供不可编辑的虚拟“未分类”分组；用户 Category 支持创建、重命名、删除和独立排序。删除 Category 只将所属 roots 归入未分类，不删除 Event 或破坏 hierarchy。
- hierarchy 移动到下层时清除旧的直接 Category；下层解除关系成为新 root 时继承原 root Category。Category 不拥有 status、duration、run_segments、completion 或 Category 状态。
- World overview 按 Category 用户顺序从左到右、从上到下展示卡片；有未分类 root Event 时追加虚拟“未分类”卡片，空用户 Category 仍显示。Category detail 只展示该 Category 的 root trees 与 descendants，Event sibling ordering 保持原有相对顺序。
- 从 Category detail 新建 root Event 时直接采用当前 Category；从虚拟“未分类”detail 创建时 `category_id` 保持 null。下层 Event 继续从父 Event 菜单创建并继承 root Category；Routine 不进入 World。
- 两层结构不再提供 Category 展开/折叠 UI；既有 Category collapse preference 作为无害兼容数据保留但不再参与 World 展示，不为此增加 migration。Event tree 的 session 内展开/折叠继续保留。

### 10.11 v0.2 F7：时间复盘

- “记录”栏目以日总结与周总结复盘真实主动执行时间；事实来源仅为 Event 的 direct run_segments，不使用 aggregate duration，waiting、paused、pending 和 completed 状态本身不产生统计时间。
- Jax 统计日为本地时间前一日 23:00 至当日 23:00；segment 以与统计窗口的 overlap 裁剪，未结束的 running segment 截止当前时间。周从周一开始，至周日 23:00 结束；当前日/周可显示进行中数据。
- 时间按 Event 的当前 hierarchy 向上找到 root，并按 root 当前 Category 动态归属；null 归入虚拟“未分类”。Category 后续调整会重新解释历史统计，第一版不冻结 Category snapshot、不新增 summary 表或 schema。
- 日总结显示按时长降序的 Category 横向条与占比；周总结显示七天真实时长的 Category 堆叠柱和全周 Category 汇总。Category identity 基于 id，未分类使用中性样式。

### 10.12 v0.2 F8：Routine / 日常

- Routine 是独立于 Event 的长期重复事项模板，不创建或复用 Event，不进入 World，也没有 Event hierarchy 或 completed 生命周期；主导航新增“日常”。
- Routine 直接关联现有 nullable Category，支持每天、工作日、周末和至少选择一天的指定星期；“今日”按本地日历日期动态派生，不提前生成 pending execution。
- RoutineExecution 以 `routine_id + occurrence_date` 保证每日最多一轮，真正开始时创建，状态仅为 running、paused、completed；completed 当日保留，次日按 recurrence 重新呈现未开始，不记录 missed。
- RoutineExecution 使用独立 run segments。Event 与 RoutineExecution 共用全局唯一 running：开始任一类型会暂停另一类型并关闭其开放片段，完成后不自动恢复此前对象。
- Windows 正常关闭暂停 running Event 或 RoutineExecution；Android 后台、锁屏和进程恢复继续依赖持久化状态与开放片段，不自动暂停。
- Routine 时间与 Event direct segments 一起进入日/周总结，共用 23:00 overlap 与当前 Category 动态归属；Category 删除将 Routine 归入未分类，停用/重新启用不删除历史。
- 第一版 Routine 为稳定顺序的 flat list，不提供物理删除、waiting、复杂 recurrence、SOP、提醒、streak、missed 或评分。

## 11. v0.1 不包含的内容

- Windows 与 Android 之间的数据同步
- 服务器、账号和登录系统
- 云备份、数据导入或数据导出
- 循环事件、子任务、提醒、标签、分类和优先级
- 多个事件同时处于 `running`
- 编辑历史记录
- F7 时间复盘以外的统计报表和数据分析
- 最终视觉设计和复杂 UI 动效
- 对断电、系统崩溃或强制结束进程场景下的绝对精确计时恢复保证

## 12. 建议实现顺序

为遵守“一次只增加一个可独立验证的行为变化”，建议依次实现：

1. 建立 Core、Data、UI 三层项目骨架。
2. 创建事件。
3. 编辑事件。
4. 删除事件。
5. 开始执行与计时。
6. 限制同一时间只能运行一个事件。
7. 暂停和恢复事件。
8. 完成事件并生成历史记录。
9. 查看和删除历史记录。
10. 自动保存和启动恢复。
11. 手动保存。
12. 正常关闭时自动暂停。

每一步开始前均应先确定对应规则和测试；每一步完成后均应运行全部已有测试。

## 13. v0.2 今日统一执行入口

- 一级导航固定为“首页 / 今日 / 世界 / 日常 / 记录”：首页回答现在正在做什么，今日回答今天准备做什么，世界管理 Event 长期结构，日常管理 Routine definition，记录复盘过去时间。
- “今日事项”只包含明确加入当前 Jax day 的 Event，不等于全部 unfinished Event；“今日日常”包含 active 且 recurrence 命中当前 Jax day 显示日期的 Routine。两个分区分别排序，不建立 Event/Routine 混合顺序。
- Jax day 使用设备本地时间 23:00 切换。逻辑日期 `YYYY-MM-DD` 表示前一自然日 23:00 至该日 23:00；Today、Routine occurrence/weekday 和 Daily Summary 共用同一个 JaxDay 规则。
- Event 今日计划是独立的按日关联，包含 Event、逻辑日期和当日顺序；不改变 status、hierarchy、Category、World sibling order、duration 或 history。加入时追加到当日末尾，使用上移/下移调整独立顺序。
- World 是 Event 正式创建和长期管理入口，并提供加入今日/移出今日。completed Event 不能主动加入或移出；恢复为 paused 后可重新加入。running Event 不能移出，waiting Event 可以移出且状态保持 waiting。
- 在单个 World Category detail 中可进入临时批量选择模式：仅可选择当前可见的未完成且尚未加入当前 Jax day 的 Event，并按该 detail 的结构显示顺序一次性追加到 Today 末尾。选择不跨 Category、不联动 parent/child，completed 与已在今日 Event 禁用；批量操作只修改 Today plan，不改变 Event 事实或 World 结构。
- 从任意入口开始或恢复 Event 时自动确保当前 Jax day plan 存在。Event 完成后保留在当天 Today，下一 Jax day 不继承；跨 23:00 仍 running 的 Event 自动进入新 Today，且不自动暂停。
- Routine 不需要手动规划。跨 23:00 仍 running 的上一 occurrence 继续使用同一 RoutineExecution，新 Today 显示它且不创建同名第二 occurrence；时间统计仍按 23:00 裁剪。
- Today Event 显示 ancestor breadcrumb，但不复制 hierarchy、Category CRUD 或完整 World tree。Today 与日常/World 可共用现有 Core 执行动作，全局 Event + RoutineExecution 最多一个 running 的约束不变。
- Today plan 本身不产生执行时间；日/周记录继续只统计 Event 与 Routine run segments。
