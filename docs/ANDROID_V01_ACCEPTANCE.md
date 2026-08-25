# Jax Android v0.1 Debug 验收记录

## 环境

- 模拟器：Pixel 7 配置，Android 16 / API 36，`emulator-5554`
- application ID：`com.example.jax`
- 构建类型：Debug

## A1：Android 应用身份确认

`namespace`、`applicationId`、Kotlin package 和源码目录均为 `com.example.jax`，无需修改或提交。

## A2：Android SQLite 契约

`integration_test/android_sqlite_contract_test.dart` 在模拟器实际 `sqflite` 环境通过，覆盖 CRUD、开始/暂停/恢复/完成、单一 `running`、事务回滚、外键级联、自动持久化、手动 checkpoint、关闭重开恢复及 `PRAGMA foreign_keys = ON`。`wal_checkpoint(FULL)` 在 Android 上成功执行，未发现需要修改 Data 的平台差异。

## A3：running 恢复与生命周期

自动化测试 `test/data/running_recovery_test.dart` 验证数据库重开后保留 `running` 和开放片段，并按重开时的真实时间戳继续计算持续时间。

模拟器以一个已持久化的 `running` 事件和 `ended_at_utc = NULL` 开放片段进行以下 Debug 验收：

```powershell
adb shell input keyevent 3
adb shell am start -n com.example.jax/.MainActivity

adb shell input keyevent 4
adb shell am start -n com.example.jax/.MainActivity

adb shell input keyevent 26
adb shell input keyevent 26
adb shell wm dismiss-keyguard
adb shell am start -n com.example.jax/.MainActivity

adb shell am force-stop com.example.jax
adb shell am start -n com.example.jax/.MainActivity
```

Home、Android 返回键、锁屏/解锁和 `am force-stop` 后重新进入均保持 `running`，开放片段未被关闭，界面持续时间从约 `00:00:12` 增长至 `00:01:05`，离开期间被计入。未出现意外 `paused`。

测试边界：`am force-stop` 会终止进程并将应用置为 stopped 状态，只有显式重新启动后才运行；它比一般低内存回收更强，但不等同于系统在缓存进程中进行的正常低内存回收。本验收用于证明 Jax 不依赖退出回调、后台计时器或进程存活，并能从已提交的 SQLite 状态恢复；系统低内存回收无法在一次确定性的模拟器脚本中完全复现。

## A4：手机主框架响应式布局

Widget 测试覆盖 360×800、2 倍文字缩放和 1200×800 桌面窗口：手机使用底部 `NavigationBar`，桌面继续使用 `NavigationRail`，保存状态和页面切换均无 overflow。

Pixel 7 模拟器 Debug 人工验证确认：保存状态位于手机 AppBar 的独立状态行，保存按钮可触控，事件/记录底部导航显示完整，页面内容和 FAB 位于导航栏上方；现有 `running` 事件继续显示并计时。Windows 集成流程复跑通过。

## A5：事件与记录页面手机适配

320×700、1.5 倍文字缩放 Widget 测试覆盖 pending/running/paused 长名称、全部状态操作、列表滚动、新建对话框返回关闭、长历史名称、时间文本和历史删除入口。手机事件卡片将名称、状态和触控操作纵向排列，历史卡片完整显示时间与持续时长；列表保留底部空间，避免 FAB 遮挡。

`integration_test/android_v01_workflow_test.dart` 在 Pixel 7 模拟器的真实 `sqflite` 环境完成创建、单一 `running` 阻止、暂停、编辑、恢复、完成、历史查看、数据库关闭重开、历史持续时间恢复和历史删除。软键盘输入、对话框、底部导航及主要触控操作均通过。

本增量同时修复一个共享恢复问题：Controller 启动时现在会为未完成事件和历史事件都加载执行片段，避免应用重启后历史持续时间显示为 0。该修复复用同一 Repository，不改变 Core 或 schema。
