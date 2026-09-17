# Routine 等待执行

## 审计与状态语义

此前 Scheduled / On-demand 共用 RoutineExecution，只有 running、paused、completed；未开始不创建 execution。状态按字符串落库，旧 CHECK 限制为这三个值。RoutineService.start 创建 execution/segment，pause 关闭 segment，resume 使用原 execution 新开 segment，complete 关闭开放 segment，或直接完成没有开放 segment 的 execution。Home running 的更多菜单支持修改开始时间、完成和修正结束时间，Today 提供直接暂停/完成，两平台复用 Flutter 页面。

Event 已有 waiting 与关闭/重新创建 RunSegment 的实现，Home Waiting 原先只显示 Event。本轮复用其语义和全局运行切换规则，不改 Event 状态机。Home 恢复原来会暂停其他 running 对象；Routine 数据事务也执行相同切换，并保证一个 running。

新增领域状态 waiting：流程尚未结束，但当前无主动投入。保持 paused 的原语义。允许 running → waiting、waiting → running、waiting → completed；不提供 waiting → paused 快捷转换。

## 执行与身份

- running → waiting：同一事务把当前 segment 的 endedAt 设置为真实当前时间，并将 execution 置为 waiting。释放 running slot。
- waiting → running：保留 execution ID、routine ID、occurrenceDate，创建新 segment；事务暂停已有 running Event/Routine。
- waiting → completed：保留已关闭的 segments，写 completedAt，不创建新 segment。
- 点击时重新读取 execution，已完成或不存在的旧引用不能再次恢复。
- 全局加载所有 waiting executions，不局限于前一日/当前 occurrence，也不依赖 Routine 当前启用、recurrence 或 temporal window。
- 到 ideal/latest、23:00 或跨多个 JaxDay 不修改等待执行。时间戳始终记录真实时间。

Record 继续累加 segment.durationAt，不包含等待空档；10:00–10:10 和 10:45–10:50 共 15 分钟。等待后直接完成则只有前 10 分钟。无 waitingDuration 字段、专用 timer 或通知。

## Home / Today / Routine

Home 原 Waiting 区合并 Event 与 Routine，共用计数、前四项预览和展开入口。Routine 显示所属类别、等待中及继续/完成。Running Hero 的更多菜单把等待放在完成同一层级；Today 正在进行行直接提供等待按钮，沙漏图标与暂停区分。

Today 的等待执行在持续事项中展示，每行绑定 execution ID。对应 Routine 的 temporal projections 被抑制，未配置时间的 Scheduled 普通行也排除等待对象；避免同一执行同时出现在现在需要处理/稍后。等待结束后重新按既有分区规则判断下一 occurrence。

TimeRecommendationRule 与候选提供器均排除 waiting；On-demand Quick Actions 也排除当前等待对象，避免与 Home Waiting 重复。Routine 管理列表显示等待中，On-demand 入口显示继续。恢复暂停仍显示原来的恢复文案。

## 数据迁移与 Sync

schema 24 使用单次 ALTER TABLE ADD COLUMN 增加 is_waiting，默认 0。受约束：只能是 0/1，且 1 必须对应原 status='paused'。这是数据层的兼容编码，领域和 Sync 只暴露单一 waiting 状态；旧 paused 保持 is_waiting=0。

该方案保留原表、主键、外键、索引及同步触发器，不使用 writable_schema，不删除重建用户表，不更新旧行时间戳或 dataset generation。所有常规 execution 写入同步设置标记，恢复/完成清零。

Sync 协议 11：快照将存储编码转成 status=waiting 并移除标记，Apply 逆向映射。旧 protocol 10 baseline 只升级版本号，保留 payload/metadata/generation；更早 baseline 沿用既有升级链。旧 schema 数据库须先由新版客户端正常升级，不能直接用旧客户端同步新等待语义。Compare、冲突选择、事务回滚和 tombstone 继续沿用统一记录机制。

## 第一版边界

未增加 Event 或 Routine 的完整状态转换日志。segments 精确保留主动执行区间和中间空档，当前等待起点可由 execution.updatedAt 与末段结束时间判断；在多次暂停/等待交替且已完成后，不能仅凭空档区分每次暂停与等待。以后如需逐段标注等待历史，应增加统一状态转换审计，不从空档猜测。本轮不绘制等待时长时间线。

测试覆盖 Scheduled/On-demand 等待/继续/直接完成、15 分钟真实统计、旧引用拒绝恢复、与 Event/Routine 全局切换、超过 latest/跨多个 JaxDay、Home/Today 去重、两平台按钮操作、旧 schema 23 含执行记录迁移、Sync 往返/compare/冲突/回滚及旧 baseline。

## 最终验证（2026-09-15）

完整测试 417/417 通过（新增 14 项），Dart 静态检查无问题，git diff --check 通过。Android 360px / Windows 1200px 的 Scheduled、On-demand 操作测试通过，两端 debug 构建成功。本轮未安装真机、未修改真实数据库或同步基线。

APK SHA256：2A3A5AF2E6C6841DEE151735232404E99E33B888834CFE1DA5DC1E53D0B99DCB

