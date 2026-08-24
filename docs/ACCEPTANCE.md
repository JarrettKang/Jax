# Jax v0.1 验收记录

验收日期：2026-08-24

## PRD 行为验收

1. 通过：创建非空事件，生成且不显示唯一 ID。
2. 通过：允许多个同名事件并按 ID 区分。
3. 通过：编辑、确认删除 pending。
4. 通过：pending 可开始并计时。
5. 通过：第二个开始/恢复请求被阻止，数据不变。
6. 通过：running 可暂停，暂停期间不计时。
7. 通过：paused 可编辑和确认删除。
8. 通过：paused 可恢复，多段时长累计。
9. 通过：running 完成后从事件页移入记录页。
10. 通过：历史记录保存开始、结束和排除暂停后的持续时间。
11. 通过：历史记录可查看并经确认删除，片段级联删除。
12. 通过：每次变更自动提交 SQLite，真实关闭/重开 Repository 后恢复。
13. 通过：全局手动保存有成功/失败反馈，不生成备份或改变业务状态。
14. 通过：可取消退出请求自动暂停并保存；失败阻止退出；重开保持 paused 且关闭期间不计时。
15. 通过：M0–M12 每阶段均在完整历史测试通过后独立提交。

## 自动化证据

- Core/Data/UI：`flutter test`，43 项通过（加入最终集成依赖前的 M12 阶段基线）。
- 端到端：`flutter test integration_test` 通过完整 PRD 工作流，并在真实 SQLite 文件关闭重开后确认 B 为 paused。
- 窗口关闭：UI 测试向 Flutter Windows 生命周期发送真实可取消退出请求，验证允许/阻止关闭的响应；Core 与文件数据库测试验证暂停事务和重启计时。

## 最终关卡结果

- `flutter analyze`：通过，0 issues。
- `flutter test`：通过，43 项 Core/Data/UI 测试全部成功。
- `flutter test integration_test`：通过，1 项完整 Windows 工作流成功。
- `flutter build windows --release`：通过，产物为 `build\windows\x64\runner\Release\jax.exe`。
- Release 隔离环境烟测：通过；在独立临时 `APPDATA` 创建 `Jax\jax.db`，收到正常窗口关闭请求后以 exit code 0 退出。

## 范围核对

未实现 Android、服务器、同步、账号、云备份、导入导出、循环事件、子任务、提醒、标签、分类、优先级、并行 running、历史编辑、统计报表或复杂视觉动效。
