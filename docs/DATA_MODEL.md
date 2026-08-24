# Jax v0.1 数据模型

数据库 schema version 为 `2`，时间均以 UTC Unix 毫秒整数保存，UI 显示时转换为设备本地时间。

## events

| 字段 | 类型 | 约束/含义 |
| --- | --- | --- |
| `id` | TEXT | 主键；程序生成且 UI 不显示 |
| `name` | TEXT | 非空，trim 后长度大于 0；允许同名 |
| `status` | TEXT | `pending`、`running`、`paused`、`completed` |
| `first_started_at_utc` | INTEGER NULL | 第一次开始时间 |
| `completed_at_utc` | INTEGER NULL | 完成时间 |
| `created_at_utc` | INTEGER | 创建时间 |
| `updated_at_utc` | INTEGER | 最后变更时间 |

## run_segments

| 字段 | 类型 | 约束/含义 |
| --- | --- | --- |
| `id` | TEXT | 主键 |
| `event_id` | TEXT | 外键到 `events.id`，事件删除时级联删除 |
| `started_at_utc` | INTEGER | 本段开始时间 |
| `ended_at_utc` | INTEGER NULL | 空值代表本段正在运行 |
| `created_at_utc` | INTEGER | 片段创建时间 |

实际持续时间等于一个事件所有执行片段的时长之和，因此暂停和软件正常关闭后的时间不会计入。`pending` 没有片段；`running` 有一个开放片段；`paused` 和 `completed` 没有开放片段。Core 与 SQLite 事务共同保证全库最多一个 running 事件。

事件系统查询所有非 completed 事件；记录系统查询 completed 事件。记录删除就是删除 completed 事件，并由外键级联删除其执行片段。
