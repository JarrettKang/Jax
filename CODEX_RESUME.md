# Jax v0.2 开发恢复点

- 当前增量：F2.2 层级 Core 规则（尚未开始编码）。
- 已完成：F1；F2.1 层级数据模型与 migration，commit `8878e64 feat: add event hierarchy data model`。
- 测试：全部 76 项自动化测试、Windows Debug 集成、Windows v2→v3 migration、Android 模拟器 sqflite v2→v3 migration、Android SQLite 契约和 `flutter analyze` 均通过，无失败测试。
- 数据库：当前 schema version 3；v2→v3 migration 已完成并验证；旧 Event 默认 `parent_event_id = NULL`，事件、状态、时间和 run_segments 保留。未对 Android 真机真实数据库执行 migration。
- Git：F2.1 提交后工作区干净；本文件用于安全暂停恢复。
- 恢复后的第一步：先读取 PRD、`Development_plan_v0.2.md` 与本文件，核对 Git/schema 后，为 F2.2 新建“设置/移动/解除关系、self-cycle、descendant-cycle、候选范围和有下层禁止删除”的 Core 测试；先运行这些测试确认失败，再实现共享 Core 规则。
