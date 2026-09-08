# World compact hierarchy map 验收（2026-09-08）

本次仅调整 World overview 及共享树引导线，不改变业务模型。

## 设计与实现

1. 原界面主要依赖缩进，连接轴未与父节点控件中心对齐；重复副标题和 Category Card 留白削弱了树的连续感。
2. 新 connector 由父节点向下短竖线、祖先延续竖线、当前层竖线与水平分支组成；根节点不连接到 Category。
3. 从同级可见列表计算 `isLastSibling`，递归传递 `ancestorHasNextSibling`。末兄弟在行中点终止，非末兄弟贯穿整行；折叠不渲染子行及向下连接。completed 节点仍参与原层级。
4. 普通节点由实测 72dp 降至 48dp：去除默认副标题、额外垂直 padding，统一 leading 和操作区；不缩小标题字体（16sp）。有长标题或窄屏摘要时允许增高。
5. overview 不再显示“尚无计划”，详细信息仍由 WorldNode Detail 承担。
6. 仅 current Plan 有摘要：有 next 项显示“N 个下一步”，否则“当前计划”。标题可用宽度至少 260dp 时同行，窄屏放轻量辅助行。
7. Category 改为紧凑 section header：颜色点、名称、根节点计数、添加根节点、More，以及分隔线；不是树的业务父节点。
8. More 使用中性色 18dp 图标，仍保留至少 48×48dp 操作区；有 children 的主行与展开按钮共用 toggle，leaf 主行无操作，More 第一项“查看详情”进入既有详情页。
9. Category 沿用原本地折叠偏好；分支以 `world-branch:<nodeId>` 命名空间复用同一 UI-only store，重建和重启恢复，不进入 Sync snapshot。
10. 每级缩进 16dp，视觉深度沿用最多 7 级上限。390dp 窄屏 fixture 验证六层节点和最深层 More 可操作；不改变真实 parentId。
11. 长名称最多两行并省略，不挤占 More；详情可查看完整名称。父节点略加粗，叶节点对齐，focus 为轻量标记。

## 视觉与数据验收

14. Windows Debug 原生窗口使用隔离 SQLite fixture（18 节点、2 分类、current Plan、completed 节点、六层长名称），目视检查主要树形和摘要；原生集成测试通过。没有向真实 Windows 数据库写入 fixture。测试结束后已恢复普通 main 入口的 Windows Debug 构建。
16. World 与 Planning/移动选择器继续复用 `WorldNodeTreeGuideFrame` / `WorldNodeTreeVisualContext`，选择器仅补充展开子节点标志；候选资格、reparent 和防环规则未改变。
17. schema **21**、Sync protocol **8** 均不变。无 migration，无 sync apply，无 Last Successful Sync Baseline 更新。

Private device/data evidence omitted; engineering behavior is described separately.

Private device/data evidence omitted; engineering behavior is described separately.

Private device/data evidence omitted; engineering behavior is described separately.

Private device/data evidence omitted; engineering behavior is described separately.

## 测试与交付

18. `flutter test`：**289 tests passed**；覆盖 sibling continuation、末节点、根节点、折叠恢复、reparent 防环、current Plan 摘要、48dp 点击区、六层长名称、窄/宽屏及零业务写入。Windows 原生 `integration_test/compact_world_map_test.dart` 另通过。
19. `flutter analyze`：**No issues found**。Windows Debug / Android Debug 构建均成功。
20. 实现、测试、PRD 与 Development Plan 同一提交交付；commit hash 见本次交付回复及 Git 日志（避免在提交内容内自引用 hash）。
