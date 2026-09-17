# 电子管家名称

## 产品语义与默认值

Jax 是保留的项目/技术标识，也可以由用户主动选择为自己的管家名字。正常 App 内管家身份始终来自 assistantName，不存在固定 Jax 产品角色加另一个助手角色。默认值只在 lib/core/preferences/app_preferences.dart 的 defaultAssistantName 定义；UI、存储和测试通过该配置读取，fork 可修改这一处。第一版不加入 persona、头像、语音或首次启动命名流程。

名称保存前 trim，不改变大小写。长度最多 24 个用户可见字符（Unicode grapheme cluster），支持中文、英文、组合字符和 emoji。空白显示“名称不能为空”，超长显示“名称最多 24 个字符”，保存不可用；不静默恢复默认或截断输入。复用 Flutter 已依赖的 characters 1.4.1，现显式声明，无包版本升级。

## 原设置审计与存储选择

原项目没有通用 AppSettings 或普通 Settings 页面。World/Routine 的展示折叠状态是独立 SQLite 偏好表，Windows Sync 存储配置是本地 JSON，两者不参与业务快照 Sync。没有已有 assistantName/user nickname。

新 AppPreferences 仅包含 assistantName，沿 core/preferences + data/preferences 分层。生产通过 main 注入 FileAppPreferencesStore，文件为现有 jax.db 同目录的 app_preferences.json；Windows 通常在 APPDATA/Jax，Android 在应用私有 databases 目录。两端实现一致，但名称是设备本地，不随业务 Sync 同步。

配置缺失或没有 assistantName 时返回默认值，读取不创建文件、不写数据库，无 schema migration、无 Sync protocol bump（仍为 schema 24 / protocol 11）。显式保存才写 JSON；保留其他配置键，先写并 flush .pending 文件，再 rename 替换正式文件。写入失败保留旧配置，成功后才发布新名称。损坏配置或读取异常在设置页显示重试，不静默覆盖；保存失败在编辑对话框提示。

测试/嵌入 App 未注入生产 Store 时使用 InMemoryAppPreferencesStore。AppPreferencesController 负责首次读取、保存后立即通知 Home/Settings，加载或保存未完成时阻止并发保存，异步结果不会通知已释放页面。

## UI 与文案范围

顶栏齿轮 → 设置 → 管家的名字，显示当前值。点击打开“你的管家叫什么？”取消/保存对话框，支持 Enter 提交；Settings 返回不会改变 Home Category 上下文。

Home Root 询问上方显示 assistantName；Temporal 主推荐显示“{assistantName} 建议您接下来：”。名称文本可换行，Android 小屏不会挤压推荐按钮。Waiting、Category 标题、World/Planning/Today/Routine/Record 和设置模块名称不使用管家名称。App 内顶栏显示当前模块名；系统使用的 MaterialApp.title、launcher 名、包名、数据库名及 Sync identity 保持原技术标识。已完成节点提示中的“不会自动恢复节点”读取 assistantName。

GreetingResolver 仅返回时段问候，移除旧“我是 Jax”返回值及 Home 随后删除该后缀的处理，时间边界不变。

## 验证与边界

自动测试覆盖无配置/旧字段默认且不写文件、trim/大小写/中文/组合 Unicode、真实文件多次保存及重新打开、保留其他键、空白与超长拒绝、写失败原文件不变及重试、读取损坏提示与重试、异步加载/并发保存保护。

Android 360px / Windows 1400px 的实际 App widget 流程覆盖设置默认值、取消不保存、修改后 Home/Temporal 更新、重新创建 App 与 Store 后保留名称、24 字中文和英文长度下无 overflow、系统技术标识与六个导航模块不变，未创建 Event/Routine execution。

2026-09-15：完整 Flutter 测试 495/495 通过（新增 10 项），dart analyze lib test 无问题，git diff --check 通过，Windows/Android debug 构建成功。日志位于 .debug_backups/assistant_name_full.log、assistant_name_windows_build.log、assistant_name_android_build.log。随后已授权安装真机，见下述记录；未通过自动化修改真实执行事项或名称。名称是设备本地设置；后续真机安装数据保护应同时记录/备份 app_preferences.json（若存在），不要仅核对 jax.db。


Android debug APK SHA256：`8b6871d57506a44e874c65ad608ceca91e4b1b2bc26cab03b925b1d94927062f`。


## 真机安装记录

Private device rollout evidence omitted from this historical version.

## 管家身份语义修正

上一轮“产品名 + 助手名”的叙述已修正。AppBar 固定 Jax 在首页会与自定义名称形成双身份，因此替换为当前模块名，不在 Category 或业务页面额外人格化。MaterialApp.title 是系统应用描述，依据本轮范围保留；Windows runner 标题和 Android launcher label 也不动态修改。

用户可见 Jax 命中审计：

| 位置 | 分类与处理 |
|---|---|
| app.dart 主界面 AppBar | 正常流程固定身份，改为首页/今日/世界/规划/日常/记录 |
| app.dart 已完成节点对话框 | “Jax 不会自动恢复节点”改读 assistantName |
| app.dart MaterialApp.title | 系统应用描述，保留技术标识 |
| debug_sync_page.dart：检查安装、工具标题、本机数据库、安装前提 | Debug 安装包/数据库身份，保留 |
| sync_preview_page.dart：工具标题、双端数据修改确认 | 明确的 Debug Sync 数据集身份，保留 |
| windows_debug_sync_coordinator.dart：Windows/Android DB 不可读、Debug 未安装、run-as 不可读、选择同步存储位置、Debug 安装诊断 | 开发工具与数据库身份，保留 |
| main.dart 项目根目录错误、platform_database.dart 平台支持错误 | 技术诊断，保留 |
| Android label、Windows main.cpp/Runner.rc 系统标题和元信息 | 本轮允许保留的系统/项目标识 |
| Home、Waiting、Empty state、greeting、Settings、Today、Planning、World、Record | 无其他固定 Jax 管家身份文案；不新增 onboarding/通知 |

Butler 仍只在 defaultAssistantName 定义，UI 没有硬编码需删除。Home 原有名称读取不变，无需新增 provider；对话框使用现有 AppPreferencesController。已有 JSON 值不改写，未配置仍使用默认，不区分老用户/新用户，也不自动给开发者改名。无存储迁移、schema 或 Sync 修改。

2026-09-15 语义修正验证：完整 Flutter 测试 495/495 通过，额外强化的自定义名字对话框回归 7/7 通过，dart analyze lib test 无问题，git diff --check 通过；Windows/Android debug 构建成功。双平台名称流程覆盖默认值、Alfred/Jax/中文、重启保留、长名称、无固定 Jax+自定义名称双身份。日志见 .debug_backups/assistant_identity_full.log、assistant_identity_dialog.log、assistant_identity_windows_build.log、assistant_identity_android_build.log。此前真机安装记录为上一版本，本次语义修正随后已获授权安装，见下。


语义修正版 Android APK SHA256：`6e9a85b870e99fd09da681e975ec2135b901a6aed4cd58877d658c58ab4c3675`。


### 语义修正版真机安装

Private device rollout evidence omitted from this historical version.

