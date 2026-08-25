# Jax v0.2 开发计划

## 1. 文档信息

- 需求基线：`PRD.md`
- 历史基线：`Development_plan.md`、`Android_v0.1_Development_plan.md`
- 目标平台：Windows、Android
- 当前增量：F1：首页
- 状态：F1 已完成
- 更新日期：2026-08-25

## 2. 统一执行规则

- 延续 Core + Data + UI、Local First、小步增量和 Windows/Android 共用业务规则及数据模型的原则。
- 每个功能先确定验收条件并添加有效测试，再做最小实现；新增测试和全部历史测试通过后，分别完成 Windows、Android Debug 验收和静态分析，最后创建独立 Git commit。
- 日常增量不生成 Release；不得删除或跳过测试、降低验收标准，也不得借当前功能重构无关模块。
- 产品行为变化最小更新 `PRD.md`，开发与验收过程记录在本计划；v0.1 开发计划保持为历史基线。

## 3. F1：首页

### 3.1 功能范围与验收条件

- Windows NavigationRail 和 Android/窄屏底部导航统一增加首项“首页”，启动默认进入首页，原事件、记录及全局保存能力保持可用。
- 首页依据设备当前本地时间显示 PRD 定义的五段问候语；全部边界使用注入式 Clock 确定性测试，并在进入、返回首页或跨越时间边界后刷新。
- 无 `running` 事件时显示可点击的“我们来做点什么？”，点击只进入事件栏目。
- 有 `running` 事件时只显示“当前正在执行：”及正确事件名称，不显示其他状态事件或额外快捷功能。
- start、pause、resume、complete 及应用恢复后，首页读取并反映事件系统的真实状态。

### 3.2 三层影响

- Core：增加轻量、无 Flutter 依赖且可注入时间测试的共享问候语规则。
- Data：复用现有 Event Repository 和 SQLite，不修改 schema、migration 或持久化语义。
- UI：增加共享 Home 页面；在现有宽屏 NavigationRail 和窄屏 NavigationBar 中增加入口，仅做必要响应式布局。

### 3.3 自动化测试

- Core：问候语全部时间边界及本地时间语义。
- UI：无/有 `running` 状态、点击跳转、只选择真正的 running 事件，以及 start/pause/resume/complete 状态同步。
- 响应式导航：首页 / 事件 / 记录顺序、默认首页、Windows 宽屏桌面导航、手机窄屏底部导航和大字体无 overflow。
- 回归：全部 Core、Data、Widget 与现有 Windows/Android 集成测试；运行 `flutter analyze`。

### 3.4 Debug 验收

- Windows：验证默认首页、当地问候、点击跳转、完整状态同步、原事件/记录/保存能力及正常关闭自动暂停规则。
- Android 模拟器：验证默认首页、三项底部导航、当地问候、完整状态同步、窄屏/大字体、返回行为、保存和既有生命周期规则。
- 只有共享组件的实际风险无法由 Widget 与模拟器覆盖时，才进行最小真机 Debug 验收；不得清除或破坏真机现有数据。

### 3.5 Git 与完成状态

- 文档、测试和实现作为 F1 完整功能提交，建议提交信息：`feat: add shared Jax home page`。
- 完成条件：全部自动化测试、静态分析和双端 Debug 验收通过，diff 无无关修改，独立提交后工作区干净。
- 当前状态：已完成。问候语边界、首页状态、响应式导航及全部历史自动化测试共 70 项通过；Windows Debug 集成测试、Android 模拟器 Debug 完整流程和 Android `sqflite` 契约测试均通过；`flutter analyze` 无问题。模拟器主程序人工可见性检查确认当地问候、三项底部导航和首页窄屏布局正常。F1 未修改 Data 或 SQLite schema，未执行 Release。
