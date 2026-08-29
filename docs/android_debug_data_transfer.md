# Windows → Android Debug 数据复制

`tool/copy_windows_data_to_android.ps1` 把 Windows 当前 Jax 业务数据库的一致性快照复制到一个明确选定的 Android Debug App。它是开发验收工具，不是同步、合并或正式导入功能。

## 前提与运行

- Android 设备已开启 USB debugging，并已接受当前电脑的授权提示。
- 使用当前源码；脚本默认构建并通过 `adb install -r` 更新 Debug APK，保留 App 数据。
- 包必须支持 `run-as`。脚本固定默认为 `com.example.jax`，无法确认 debuggable 时会停止。
- 关闭 Windows Jax 不是必需条件；脚本通过 SQLite `VACUUM INTO` 从 live database 生成包含 WAL 最新事务的一致快照。

单台已授权设备：

```powershell
.\tool\copy_windows_data_to_android.ps1
```

多台设备时必须指定 serial：

```powershell
.\tool\copy_windows_data_to_android.ps1 -Device <device-serial>
```

若已手动安装当前 Debug APK，可使用 `-SkipBuild`。恢复最近一次较早备份：

```powershell
.\tool\copy_windows_data_to_android.ps1 -Device <device-serial> -SkipBuild -RestoreLatest
```

## 数据与安全

默认源是 `%APPDATA%\Jax\jax.db`，目标是 Android app sandbox 中的 `databases/jax.db`。脚本会：检查唯一目标设备、更新 Debug APK、验证 `run-as`、force-stop App 并先拉取原始 Android DB/WAL/SHM 形成保留其原 schema 的一致备份；随后才启动当前 Debug App 一次以运行应用自身的正常 schema migration，并确认已到 v12；最后验证 Windows snapshot、移除目标旧 WAL/SHM、写入并逐字节回读校验，再启动 App。

Android 导入前备份保存在 `.debug_backups/android/<timestamp>/jax_android_before_import.db`。临时 Windows snapshot 位于 `.debug_snapshots/`，成功后删除。两个目录均被 Git 忽略，因为它们包含真实生活数据。

迁移包含 SQLite 内的 Event、hierarchy、Category 与颜色、Routine、Routine Category、Today plan、RoutineExecution、Event/Routine run segments、状态、waiting 和 order。当前 SQLite 中的 Category 折叠 preference 也会随库复制。窗口大小、hover、临时 selection、系统 cache 和其它平台沙盒内容不会复制。

时间戳保持原始 UTC 整数，不做时区转换。open segment 和 running 状态不会被改写或新建；Android 启动后仍由现有逻辑按 `startedAt → now` 计算 duration。

常见失败会在覆盖前停止：ADB 不存在、设备未授权、无设备、多设备但未指定、包未安装或不可 `run-as`、源库缺失、schema 非 v12、integrity/foreign-key 检查失败、Android 备份或回读验证失败。

复制完成后 Windows 与 Android 会独立变化，新记录不会自动同步或合并。
