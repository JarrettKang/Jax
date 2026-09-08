# World tree interaction priority adjustment

2026-09-08

高频 tree browsing 使用主行大点击区域。原先主行打开 Detail、chevron 单独折叠；
现在有 children 的主行及 chevron 共用 `_toggleBranch`，leaf 的 `onTap` 为 null，
保留对齐和 48dp 起步的布局。focused、completed、有/无 Plan 均不改变浏览资格。

More 第一项为“查看详情”，调用原 `_openNodeDetail`，完整复用
`WorldNodeDetailPage`，没有修改详情内容或其它页面入口。

继续使用 ListTile 内置 InkWell 和独立 IconButton/PopupMenuButton 的手势竞争，
子按钮获胜后不会再激活行点击；没有额外叠加父 GestureDetector。
focus、排序、添加计划等仍是菜单动作。主行和 chevron 共用现有 device-local
`world-branch:<nodeId>` 持久化源，setState 立即刷新子树和 guide。
Category header 和 Planning/Move picker 的交互不变。

## 验证

- `flutter test`：290 项通过；`flutter analyze`：No issues found。
- 390dp Android / 1400dp Windows widget fixture：主行反复 toggle、chevron 单次
  toggle、leaf 无副作用、More 打开/关闭不折叠、More → canonical Detail、返回后
  scroll offset 和分支状态保持、六层父节点点击和 outgoing connector 刷新。
  SQLite business fingerprint 前后相同。
- 桌面 Enter/Space 行激活通过；读屏父节点动作提示随状态切换，leaf 不宣称展开。
- 独立菜单测试覆盖关注/取消关注/下移/完成均不折叠，以及 completed parent 浏览。
- 重建 WorldPage 后恢复由主行写入的持久化折叠状态；既有 Category/picker 测试通过。
- Windows 原生隔离 SQLite fixture 集成测试通过。computer-use 真实鼠标检查：
  第五层名称折叠/展开、连接线立即收起/恢复、More 首项清晰且不折叠、详情与返回
  后位置保留。无真实数据库写入。
- Android `emulator-5554` 原生隔离 SQLite fixture 集成测试通过，覆盖相同核心
  浏览/菜单/详情返回断言；ADB 手动触控检查第五层名称折叠及 chevron 单次展开，
  第六层长名称与连接线正常。Android 验收使用模拟器，本轮未安装 <device-model> 真机。
- Windows Debug 与 Android Debug 普通 main 入口重新构建成功，避免交付测试入口。

本次产品改动仅在 `lib/ui/pages/world_page.dart`。schema 21、Sync protocol 8、
所有业务模型和同步语义保持不变；未执行真实 sync apply、baseline 更新或备份恢复。
原生测试使用临时 fixture 数据库，既有真实数据库和历史备份未改动。

本轮本地日志与 Android 截图在 `.debug_backups/world_tree_*`（不进入 Git）。
交互回归复用 `test/support/world_tree_interactions.dart`；原生测试可用
`WORLD_VISUAL_HOLD_SECONDS` 暂停并接收真实点击，仅供隔离 fixture 目视检查。
