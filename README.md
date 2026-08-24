# Jax v0.1

Jax 是一个仅 Windows 的 local-first 电子管家最小可运行版本。它支持一次性事件的创建、编辑、删除、开始、暂停、恢复、完成与历史记录，并把数据保存在本地 SQLite 中。

## 运行

环境要求：Flutter stable 与 Visual Studio 的 Desktop development with C++ 工作负载。

```powershell
flutter pub get
flutter run -d windows
```

本地数据库位于 `%APPDATA%\Jax\jax.db`。程序不需要服务器即可完整使用。

## 验证与构建

```powershell
flutter analyze
flutter test
flutter test integration_test
flutter build windows --release
```

Release 可执行文件生成在 `build\windows\x64\runner\Release\jax.exe`。

## 文档

- `PRD.md`：v0.1 已确认需求与范围
- `Development_plan.md`：增量开发与验收计划
- `docs/ARCHITECTURE.md`：三层架构和关闭流程
- `docs/DATA_MODEL.md`：SQLite 数据模型
- `docs/ACCEPTANCE.md`：15 项 PRD 验收记录