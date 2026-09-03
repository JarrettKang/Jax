# Jax v0.1 开发计划

## 1. 文档信息

- 产品：Jax（我的电子管家）
- 对应需求基线：`PRD.md` v0.1
- 目标平台：Windows
- 后续目标平台：Android
- 文档状态：已确认，可直接执行
- 更新日期：2026-08-24

## 2. 当前状态

- 工作区当前只有需求与开发计划文档，尚无应用工程代码。
- 尚未创建 Flutter 项目。
- 尚未初始化 Git 仓库。
- 当前系统未检测到 Flutter 和 Dart 命令。
- 正式实施前必须先完成环境准备关卡。

## 3. v0.1 交付目标

最终交付物包括：

- 可在 Windows 本地运行的 Jax 桌面应用。
- Core、Data、UI 三层代码。
- SQLite 本地数据库。
- 完整的自动化测试。
- Windows Release 构建产物。
- 用户启动说明。
- 数据模型和架构文档。
- 与 `PRD.md` 一致的验收记录。

最终必须通过：

```powershell
flutter analyze
flutter test
flutter test integration_test
flutter build windows --release
```

上述命令全部通过，并完成人工验收后，v0.1 才算完成。

## 4. 技术方案

### 4.1 技术栈

- Flutter / Dart
- Windows Desktop
- SQLite
- UUID
- Flutter 自带状态通知机制；v0.1 不引入复杂状态管理框架。
- 注入式 Clock；计时测试不得依赖真实时间流逝。
- Windows 窗口关闭拦截；用于关闭前自动暂停并保存。

依赖只在需要它的增量中添加，不一次性安装全部依赖。

### 4.2 三层依赖规则

```text
UI → Core ← Data
```

- Core 保存实体、业务错误、Repository 接口、业务服务和用例。
- Data 实现 Core 定义的 Repository 接口，负责 SQLite 和持久化。
- UI 调用 Core 用例并展示结果，不自行决定状态转换、计时或权限规则。
- Core 不得导入 Flutter UI、SQLite 或 Windows 平台代码。
- Windows 和未来 Android 端必须复用 Core 规则和 Data 数据模型。

### 4.3 计划目录结构

```text
Butler2/
├─ PRD.md
├─ Development_plan.md
├─ README.md
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ DATA_MODEL.md
│  └─ ACCEPTANCE.md
├─ lib/
│  ├─ core/
│  │  ├─ entities/
│  │  │  ├─ jax_event.dart
│  │  │  ├─ run_segment.dart
│  │  │  └─ event_status.dart
│  │  ├─ errors/
│  │  │  └─ domain_failure.dart
│  │  ├─ repositories/
│  │  │  └─ event_repository.dart
│  │  ├─ services/
│  │  │  ├─ event_service.dart
│  │  │  └─ clock.dart
│  │  └─ use_cases/
│  ├─ data/
│  │  ├─ database/
│  │  │  ├─ app_database.dart
│  │  │  ├─ schema.dart
│  │  │  └─ migrations.dart
│  │  ├─ repositories/
│  │  │  └─ sqlite_event_repository.dart
│  │  └─ services/
│  │     └─ save_service.dart
│  ├─ ui/
│  │  ├─ controllers/
│  │  │  └─ event_controller.dart
│  │  ├─ pages/
│  │  │  ├─ events_page.dart
│  │  │  └─ history_page.dart
│  │  └─ widgets/
│  ├─ app.dart
│  └─ main.dart
├─ test/
│  ├─ core/
│  ├─ data/
│  └─ ui/
└─ integration_test/
   └─ v01_workflow_test.dart
```

具体文件可以随实现进行小范围调整，但三层边界和依赖方向不可改变。

### 4.4 Android A0 平台适配

- Android 与 Windows 使用同一 Flutter 工程、Core、数据模型、Repository 和可复用 UI，不建立 Android 专用业务层。
- 平台入口仅选择本地数据库驱动与路径：Windows 使用 `sqflite_common_ffi` 和 `%APPDATA%`，Android 使用 `sqflite` 和应用私有数据库目录。
- Windows 正常关闭自动暂停仅注册于 Windows；Android 生命周期按 `PRD.md` 的 Android v0.1 平台规则执行。
- A0 已完成 Android 16/API 36 模拟器 Debug 启动；Android application ID 确认为 `com.example.jax`。

### 4.5 Android v0.1 阶段入口

Android v0.1 的兼容性结论、平台规则、A1–A6 增量与专属验收流程见 `Android_v0.1_Development_plan.md`。本阶段继续复用现有 Core、Data schema 和 Repository 语义，只实现经测试证明必要的平台与手机 UI 适配；开发期间仅使用 Debug，全部 Debug 验收通过后等待用户决定是否进入 Android Release。

## 5. 数据模型

### 5.1 `events` 表

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PRIMARY KEY | UUID |
| `name` | TEXT NOT NULL | 去除首尾空格后不能为空 |
| `status` | TEXT NOT NULL | 四种事件状态之一 |
| `first_started_at_utc` | INTEGER NULL | 首次开始的 UTC 时间戳 |
| `completed_at_utc` | INTEGER NULL | 完成时间 |
| `created_at_utc` | INTEGER NOT NULL | 创建时间 |
| `updated_at_utc` | INTEGER NOT NULL | 最后修改时间 |

### 5.2 `run_segments` 表

每段从开始或恢复到暂停或完成的实际运行时间单独保存。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PRIMARY KEY | 执行片段 UUID |
| `event_id` | TEXT NOT NULL | 关联事件 |
| `started_at_utc` | INTEGER NOT NULL | 本段开始时间 |
| `ended_at_utc` | INTEGER NULL | 空值表示正在运行 |
| `created_at_utc` | INTEGER NOT NULL | 创建时间 |

### 5.3 数据约束

- 删除事件时级联删除其执行片段。
- `pending` 没有执行片段。
- `running` 必须且只能有一个未结束片段。
- `paused` 和 `completed` 不能有未结束片段。
- 完成记录的实际持续时间为全部执行片段时长之和。
- 时间统一以 UTC 毫秒时间戳保存，UI 转换为用户本地时间。
- 数据库从第一版开始维护 schema version 和迁移入口。
- 全库最多一个 `running` 的规则由 Core 强制执行，并在数据库事务内再次检查。

## 6. 统一增量执行流程

每个开发增量必须严格按照以下顺序执行：

1. 核对对应的 PRD 条款。
2. 先编写新增行为的失败测试。
3. 更新数据模型或迁移规则（如需要）。
4. 实现 Core。
5. 实现 Data。
6. 实现 UI。
7. 运行全部历史测试。
8. 人工验证新增行为。
9. 在验收文档中记录结果。
10. 为该增量创建独立 Git 提交。

### 6.1 Debug 与 Release 规则

- 日常增量开发默认使用 Debug 构建；每个功能必须完成对应自动化测试、全部历史测试、Debug 人工验证和独立 Git 提交。
- 小功能完成后不要求重新生成 Release。仅当计划版本全部完成并通过全量验收，或用户明确要求正式版本时，才执行 Release 构建。
- Release 构建后必须对 Release 产物本身执行关键业务流程验收，不能以 Debug 测试结果代替。
- 正式版本验收仍包括静态分析、全部自动化测试、集成测试和 Release 构建检查。

### 6.2 长期文档维护规则

- 产品行为、业务规则、用户可观察功能或验收标准发生变化时，更新 `PRD.md`。
- 软件架构、开发流程、测试策略、构建方式或工程约束发生变化时，更新 `Development_plan.md`。
- 仅修复 bug、使实现重新符合现有规则时，通常不修改这两份文档，只修改代码和测试并以 Git commit 记录。
- 同时改变产品行为和开发/架构规则时，分别更新对应文档。
- 文档遵循最小必要修改：不因小功能重写全文、不重复规则、不把已完成的小修改追加成新阶段；`PRD.md` 描述“产品应该是什么”，`Development_plan.md` 描述“如何开发和验证”。

建议提交信息：

```text
chore: establish project foundation
feat: create pending events
feat: edit pending events
```

## 7. 详细增量计划

### M0：环境和项目骨架

行为变化：项目可以在 Windows 启动，并显示空的 Jax 主界面。

执行内容：

- 安装 Flutter stable。
- 安装 Visual Studio 的 Desktop development with C++ 工作负载。
- 启用 Flutter Windows Desktop。
- 运行 `flutter doctor -v`，消除 Windows 开发相关错误。
- 初始化 Git。
- 在当前目录创建 Flutter 项目，不覆盖现有文档。
- 建立 Core、Data、UI 目录。
- 添加静态分析规则。
- 创建事件页和记录页的空状态。
- 创建测试目录和统一验证命令。

验证：

- 应用可以在 Windows 启动。
- 事件页显示“暂无未完成事件”。
- 记录页显示“暂无历史记录”。
- `flutter analyze` 和 `flutter test` 通过。

本增量不做数据库、事件创建或其他业务行为。

### M1：创建事件

行为变化：用户可以创建一个 `pending` 事件。

Core：

- 定义 `JaxEvent` 和 `EventStatus`。
- 名称执行 `trim` 后不能为空。
- 通过注入的 ID 生成器创建 UUID。
- 同名事件不执行唯一性检查。

Data：

- 建立数据库和 `events` 表。
- 实现插入事件和读取未完成事件。
- 插入操作使用事务。

UI：

- 添加“新建事件”按钮。
- 提供名称输入框。
- 空名称显示明确错误。
- 创建成功后刷新事件列表。
- 不显示事件 ID。

测试：

- 空名称和纯空格名称创建失败。
- 同名事件可以创建两次。
- 两个同名事件拥有不同 ID。
- 新事件状态为 `pending`。
- UI 不显示 ID。

### M2：编辑事件

行为变化：允许编辑 `pending` 事件名称。

Core：

- 只允许 `pending` 事件执行编辑。
- 新名称仍须满足非空规则。

Data：

- 按 ID 更新，不能按名称更新。
- 更新 `updated_at_utc`。

UI：

- `pending` 事件显示编辑入口。
- 用户可以保存或取消编辑。
- 保存失败时保留输入并显示原因。

测试：

- 合法名称编辑成功。
- 改成空名称失败。
- 同名事件只更新被选中的 ID。
- 非 `pending` 状态由 Core 拒绝编辑。

### M3：删除事件

行为变化：允许删除 `pending` 事件。

Core：

- 删除用例只允许 `pending` 和未来的 `paused` 状态。
- `running` 和 `completed` 拒绝通过未完成事件入口删除。

Data：

- 按 ID 删除事件。
- 配置执行片段级联删除。

UI：

- 删除前显示确认对话框。
- 确认后事件从列表消失。
- 取消操作不改变数据。

测试：

- 删除指定 ID。
- 同名事件不会被误删。
- 删除不存在的 ID 返回明确失败。
- `running` 和 `completed` 删除被拒绝。

### M4：开始执行和计时

行为变化：`pending` 可以变为 `running` 并显示计时。

Core：

- 实现 `pending → running`。
- 记录首次开始时间。
- 创建一个未结束的执行片段。
- Clock 必须可替换为测试时钟。

Data：

- 添加 `run_segments` 表。
- 状态更新和执行片段创建在同一事务中完成。

UI：

- `pending` 显示“开始”。
- `running` 显示当前实际持续时间。
- UI 定时刷新显示，但实际持续时间依据 Core 数据计算。
- `running` 不显示编辑或删除入口。

测试：

- 开始时间来自注入的 Clock。
- 开始后状态正确。
- 首个执行片段正确创建。
- 刷新 UI 不修改数据库。
- 不允许重复开始同一个事件。

### M5：限制单一运行事件

行为变化：全局最多只有一个 `running` 事件。

Core：

- 开始或恢复前查询当前运行事件。
- 如果已有其他事件运行，返回专用业务错误。
- 不自动暂停原事件。

Data：

- 检查和状态更新位于同一事务。
- Repository 提供查询当前运行事件的方法。

UI：

- 操作被阻止时提示“请先暂停或完成当前事件”。

测试：

- 第一个事件能够开始。
- 第二个事件被阻止。
- 原事件仍为 `running`。
- 第二个事件保持原状态。
- 失败操作不产生执行片段。

### M6：暂停事件

行为变化：`running → paused`，暂停后停止计时。

Core：

- 关闭当前未结束的执行片段。
- 使用 Clock 写入片段结束时间。
- 状态变为 `paused`。
- 暂停后的持续时间为所有已结束片段时长之和。

Data：

- 关闭片段和改变状态必须原子提交。

UI：

- `running` 显示“暂停”。
- `paused` 显示已累计时长。
- `paused` 恢复显示编辑和删除入口。

测试：

- 暂停时间正确。
- 暂停期间时间推进不增加持续时间。
- `pending`、`paused`、`completed` 不能执行暂停。
- 暂停后可以编辑和删除。

### M7：恢复事件

行为变化：`paused → running` 并继续累计时长。

Core：

- 恢复时创建新的执行片段。
- 保留首次开始时间。
- 执行单一运行事件检查。

Data：

- 新片段创建和状态变化原子提交。

UI：

- `paused` 显示“恢复”。
- 恢复后重新显示动态计时。

测试：

- 恢复不会覆盖首次开始时间。
- 暂停时段不计入实际持续时间。
- 多次暂停、恢复后累计结果正确。
- 已有其他运行事件时恢复被阻止。

### M8：完成事件并生成历史记录

行为变化：`running → completed`，事件从事件页转入记录页。

Core：

- 关闭当前执行片段。
- 写入完成时间。
- 状态变为 `completed`。
- 计算全部实际运行时长。

Data：

- 关闭片段和完成事件原子提交。
- 未完成列表排除 `completed`。
- 历史查询只返回 `completed`。

UI：

- `running` 显示“完成”。
- 完成后事件页不再显示该事件。
- 记录页显示名称、开始时间、结束时间和持续时间。
- 时间按用户当前本地时区格式化。

测试：

- 只有 `running` 可以完成。
- 完成时间正确。
- 持续时间排除所有暂停时段。
- 原事件 ID 保持不变。
- 完成事件只出现在记录系统。

### M9：删除历史记录

行为变化：用户可以删除一条已完成记录。

Core：

- 只有 `completed` 可以通过历史记录删除入口删除。
- 未完成事件不能通过该用例删除。

Data：

- 删除事件并级联删除全部执行片段。
- 删除操作使用事务。

UI：

- 历史记录提供删除入口和确认对话框。

测试：

- 删除后记录消失。
- 对应执行片段全部删除。
- 同名历史记录不会被误删。
- 取消确认不改变数据。

### M10：自动保存和启动恢复

行为变化：所有业务变更自动持久化，重启后恢复。

实现原则：

- 每个写操作只有在 SQLite 事务成功提交后才向 UI 报告成功。
- UI 不维护另一份需要单独保存的权威数据。
- 应用启动时从数据库加载数据。
- 数据库失败时显示错误，不能假装保存成功。

测试：

- 创建、编辑、删除和状态转换后，重新打开 Repository，结果一致。
- 未完成事件和历史记录均可恢复。
- 事务失败不会留下半条事件或未配对片段。
- 数据库 schema version 正确。

### M11：手动保存

行为变化：用户可以强制保存并看到结果。

Data：

- 定义全局 `SaveService.flush()`。
- 确保所有待处理写操作完成。
- 必要时执行 SQLite checkpoint。
- 返回明确的成功或失败结果。

UI：

- 在全局位置添加“保存”按钮。
- 保存期间防止重复点击。
- 成功和失败均显示反馈。
- 自动保存和手动保存成功后均更新全局“最后保存时间”，按用户本地时间显示；保存失败时不更新时间。
- “最后保存时间”仅是运行期间的 UI 状态，不触发额外数据库写入。

测试：

- 成功时显示成功提示。
- 底层失败时显示失败提示。
- 手动保存不创建备份文件。
- 手动保存不改变任何业务状态。
- 自动与手动保存成功后更新时间，失败时保留上次成功时间。
- 保存状态时间测试使用注入式 Clock / Fake Clock，不依赖真实时间等待。

### M12：正常关闭时自动暂停

行为变化：关闭窗口时，运行事件自动暂停并保存。

实现：

- 拦截 Windows 窗口正常关闭事件。
- 如果存在 `running` 事件，以当前 Clock 时间执行标准暂停用例。
- 等待数据库事务提交成功后关闭窗口。
- 没有运行事件时直接执行保存并关闭。
- 防止关闭回调重复执行。

测试：

- 有运行事件时，关闭流程调用暂停。
- 执行片段在关闭时正确结束。
- 重启后事件为 `paused`。
- 关闭到重启之间的时间不计入持续时间。
- 无运行事件时不修改事件状态。
- 保存失败时不能静默丢失数据，应阻止关闭并提示用户重试。

人工验证：

- 运行一个事件后，通过窗口关闭按钮退出。
- 重新打开 Jax。
- 确认事件为暂停状态，且关闭期间没有计时。

## 8. 测试策略

### 8.1 Core 单元测试

必须覆盖：

- 每个合法状态转换。
- 每个非法状态转换。
- 名称校验。
- 同名事件按 ID 独立操作。
- 单一运行约束。
- 多次暂停与恢复。
- 实际持续时间计算。
- 时间边界和零时长片段。
- 各状态的编辑、删除权限。

Core 测试必须使用 Fake Clock 和固定 UUID，不使用等待真实时间的测试。

### 8.2 Data 集成测试

使用临时 SQLite 数据库，覆盖：

- 表结构和迁移。
- CRUD。
- 事务原子性。
- 级联删除。
- 重启后的数据恢复。
- UTC 时间戳序列化。
- Repository 查询条件。

### 8.3 UI 测试

覆盖：

- 空列表。
- 创建、编辑和删除对话框。
- 各状态对应的按钮。
- 禁止操作时的提示。
- 保存成功和失败提示。
- 历史时间本地化显示。
- ID 不出现在界面中。

### 8.4 端到端测试

最终工作流：

```text
创建 A
→ 开始 A
→ 创建 B
→ 尝试开始 B 并被阻止
→ 暂停 A
→ 编辑 A
→ 开始 B
→ 暂停 B
→ 恢复 A
→ 完成 A
→ 在历史记录中查看 A
→ 删除 A 的历史记录
→ 重启应用
→ 确认 B 仍为 paused
```

## 9. 每个增量的完成标准

一个增量只有同时满足以下条件才算完成：

- `PRD.md` 中对应规则没有被改变或遗漏。
- 新行为拥有自动化测试。
- Core 不依赖 Data 或 UI。
- UI 没有重复实现业务规则。
- 所有数据库写入均通过 Repository。
- `flutter analyze` 无错误。
- 全部历史测试通过。
- Windows 人工验证通过。
- 架构、数据或验收文档已按需更新。
- 增量拥有独立 Git 提交。

如果某一步发现需要改变已经确认的行为，必须暂停编码，先修改并重新确认 `PRD.md`。

## 10. 环境准备关卡

正式开始 M0 前需要：

1. 安装 Flutter stable。
2. 安装或确认 Visual Studio Windows C++ 桌面工具链。
3. 运行并通过：

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
```

4. 在工作区初始化 Git：

```powershell
git init
git add PRD.md Development_plan.md
git commit -m "docs: establish Jax v0.1 requirements and plan"
```

5. 创建项目后验证：

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

安装 Flutter 和 Windows 构建工具会修改工作区之外的系统环境，正式执行时需要单独获得授权。

## 11. 最终验收流程

1. 运行静态分析。
2. 运行全部 Core、Data 和 UI 测试。
3. 运行端到端测试。
4. 执行 `PRD.md` 中全部 15 项验收条件。
5. 人工验证 Windows 正常关闭自动暂停。
6. 构建 Windows Release 版本。
7. 在干净环境启动构建产物并检查本地数据库创建和重启恢复。
8. 将验收结果写入 `docs/ACCEPTANCE.md`。
9. 确认没有实现 v0.1 明确排除的功能。
10. 标记 v0.1 完成。

## 12. P3.5：当前 running 开始时间修正

行为变化：用户可从 Home Running Hero 的 More 打开轻量时间对话框，把当前 open segment 的 `startedAt` 向前修正；Event 与 Routine 使用同一交互和 Core overlap 语义。

Core / Data：

- `ExecutionSegmentService.adjustRunningEventStart` 与 `adjustRunningRoutineStart` 校验非未来、只向前、全局唯一 running、唯一 open segment、stale identity 及跨 Event/Routine overlap。
- EventRepository / RoutineRepository 提供窄的原子更新接口。SQLite 事务在写入前重复校验 owner 状态、segment ID、expected startedAt 和跨表 overlap，仅更新原行的 `started_at_utc` 与 `updated_at_utc`。
- 不迁移 schema，不创建新 segment，不修改 owner、Today、Planning、WorldNode 或 Record 关系。跨 JaxDay 保留单一真实 segment，由既有统计 clipping 负责归属。

UI：

- Event/Routine 共用 Home 的紧凑 dialog，显示当前开始时间，并提供日期、时间选择与行内业务错误。
- 成功后 controller 重新加载 segment，Running Hero timer 立即按修正后的 startedAt 计算；保存时 stale 则保留 dialog 并显示“当前执行状态已发生变化”。

测试：

- 覆盖 Event/Routine 原位修改、segment count/identity、向后拒绝、跨类型 overlap、邻接、跨 JaxDay、planned relation 不变、stale completion、SQLite rollback/sync metadata 与手机窄屏 dialog/timer 刷新。

## 13. P4：Plan Review 与 WorldNode Detail

1. Schema v17 增加 PlanReviewNote 与 sync triggers；迁移必须只增加空结构。
2. PlanningRepository 完成 focused/waiting/ended 下的复盘增删改查，保留 createdAt，
   Plan 安全删除按 note → item → plan 顺序写 tombstone。
3. Sync protocol 5 覆盖 snapshot、fingerprint、3-way conflict、mutation/apply、
   dependency order、readiness 与 protocol 4 baseline 兼容升级。
4. Plan Detail 增加低噪音复盘区和窄屏多行编辑对话框，不强制 review。
5. WorldNode Detail 提供 overview/current/history/execution 四段只读信息；执行历史仅
   聚合 exact-node planned Event 的 direct duration。
6. 自动化覆盖迁移不变性、复盘全生命周期、同步冲突/墓碑/回滚、历史排序与过滤、
   页面读取 fingerprint 不变及窄屏布局。
7. 完整 analyze/test/build 后，先备份真实双端数据库，再做 v16→v17 rollout；
   rollout 不创建真实 PlanReviewNote、不执行真实 sync apply。
