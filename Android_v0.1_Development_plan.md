# Jax Android v0.1 开发计划

## 1. 范围与基线

- 产品规则以 `PRD.md` 为准；Windows v0.1 是已完成且必须保持兼容的产品基线。
- Android 与 Windows 使用同一 Flutter 工程、Core、Data schema 和 Repository 语义，不复制 Android 专用 Core 或业务页面。
- Android application ID 为 `com.example.jax`。
- 本阶段仅完成 Android v0.1 的本地业务适配，不包含服务器、同步、账号、通知或 Release。

## 2. 兼容性结论

- 创建、编辑和删除未完成事件、开始、单一 `running`、暂停、恢复、完成、历史记录、删除历史记录、保存状态和 UTC 时间模型均可复用现有业务实现，Core 原则上无需修改。
- Android 已通过 `sqflite` 使用应用私有 SQLite 数据库，并复用 schema 和 Repository；必须在真实 Android 模拟器验证事务、外键、flush 和重启恢复，只有测试暴露差异时才最小修改 Data。
- 现有 UI 可复用，但桌面 `NavigationRail`、AppBar 保存状态、事件操作区、历史信息、FAB 和对话框需要窄屏与触控验证，并按失败结果最小适配。
- 现有自动化测试充分覆盖共享业务规则，但 Windows FFI 数据测试不能替代 Android `sqflite` 集成测试；Android 生命周期和进程终止恢复需要专属验收。

## 3. Android 平台规则

- 切换后台、锁屏、返回键离开主页面、返回桌面和系统正常回收进程均不得自动暂停 `running` 事件。
- 只有用户明确点击“暂停”或“完成”才改变 `running` 状态。
- 重新启动后从已持久化状态和未结束执行片段恢复 `running`，根据真实时间戳计算离开期间的持续时间。
- 不依赖 UI 在后台持续刷新，不增加后台 Service、Foreground Service 或后台逐秒计时任务。
- Windows 正常关闭自动暂停继续由 Windows 专属生命周期监听处理。

## 4. 统一增量流程

A2–A5 每个增量依次执行：明确验收条件，先添加有效测试，最小实现，运行新增测试和全部历史测试，在 Android 模拟器 Debug 验证，执行 Windows Debug 回归，检查 Git diff，通过后创建独立 Git commit，再进入下一增量。不得删除或跳过测试、降低标准、复制 Core，或重构与当前失败无关的共享代码。

## 5. 开发增量

### A1：Android 应用身份确认

- 确认 `namespace`、`applicationId`、Kotlin package 和目录统一为 `com.example.jax`。
- 已一致时只记录结果并进入 A2，不创建空提交；不一致时才最小修复并验证 Debug 构建和安装。

### A2：Android SQLite 契约验证

- 在真实 Android `sqflite` 环境验证创建、编辑、删除、开始、暂停、恢复、完成和单一 `running`。
- 验证事务原子性、外键级联、自动持久化、手动 `flush()`、数据库关闭重开恢复、`PRAGMA foreign_keys = ON` 和 `wal_checkpoint(FULL)`。
- 优先添加 Android 平台集成测试；只有测试暴露平台差异时才最小修改 Data。

### A3：Android running 恢复与生命周期

- 验证后台返回、锁屏解锁、返回键离开并重进均保持 `running`。
- 通过尽量接近系统进程终止语义的 ADB 手段验证重启后恢复 `running` 和开放执行片段，离开期间按真实时间计入持续时间且不产生意外 `paused`。
- 记录使用的 ADB 命令及测试边界；同时确认 Windows 正常关闭自动暂停测试继续通过。

### A4：手机主框架响应式布局

- 手机窄屏使用适合触控的底部导航，Windows 宽屏保持桌面布局。
- AppBar、保存状态和保存按钮无 overflow，支持合理文本缩放，事件页和记录页可正常切换。
- 添加不同窗口宽度与文本缩放的 Widget 测试，不复制 Android 专用业务页面。

### A5：事件与记录页面手机适配

- 验证并最小修复各状态操作、长名称、按钮排列、历史时间文本、滚动、FAB 遮挡、对话框、软键盘和 Android 返回键。
- 在 Android 模拟器走通完整 v0.1 工作流；布局可以与 Windows 不同，业务行为必须一致。

### A6：Android v0.1 全量 Debug 验收

- 运行 `flutter analyze`，全部 Core、Data、UI/Widget 测试，Windows SQLite/集成测试和 Android 模拟器 `sqflite` 集成测试。
- 验收 Android 生命周期和进程恢复、Windows Debug 关键业务回归、Android Debug 完整 v0.1 人工流程。
- 失败时先修复并重跑相关测试及全部历史测试。全部通过后停止并报告，等待用户决定 Android Release 与真机验收。

## 6. Android 专属验收边界

- Android SQLite 测试必须使用模拟器中的实际 `sqflite`，不能以 Windows `sqflite_common_ffi` 结果代替。
- UI 计时刷新不是权威计时来源；持续时间必须由持久化 UTC 时间戳和执行片段计算。
- ADB 强制停止可用于验证持久化恢复，但不等同于系统低内存回收；验收记录必须说明这一边界。
- 日常开发和全部 A1–A6 验收只使用 Debug，不生成 Windows 或 Android Release。
