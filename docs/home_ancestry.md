# Home Category View 祖先上下文

## 审计与最小抽取

Planning 原私有 `_PlanningAncestry` 已抽为共享 `WorldNodeAncestryView(names, compact)`，保留原 WorldNodeTreeGuideFrame / WorldNodeTreeVisualContext 的 connector、自然换行与缩进算法。Planning 继续传入 Category 展示名及真实祖先，默认样式不变。Home 使用 compact 模式：11px、较弱文字颜色与连接线、1.2 行高和每行上下 1px 间距；祖先区域上下仅 4px，无 Card、背景块、图标或点击事件。

WorldNodeTreeGuideFrame 仅新增可选 guideColor，默认颜色完全不变，不复制 painter。无需交互开关或新的业务模型，祖先组件本身始终只读。

## 裁剪规则与布局

Category 是独立 metadata，不是 WorldNode。Home 只把 PlanningController.pathFor(node) 返回的真实节点路径按 id 排除当前节点后传入，不额外加入 Category。因此分类标题不重复；若真实祖先恰好与 Category 同名，仍保留，禁止按字符串裁剪。

每组顺序为 WorldNode 标题与“规划一下”、祖先链、原 PlanItem/Event 行或“还没有可执行步骤”。没有祖先时不创建 ancestry 区域，也没有占位文本或额外空白；没有候选步骤时仍显示祖先。

每层缩进 12px，最大视觉深度 5（60px），深层保留完整顺序和名称；文字自然换行、不省略、不横向滚动。Home 原 820px 内容宽度限制不变。

## 数据与范围

复用 PlanningController 已加载 WorldNode 列表和 pathFor，沿内存中的 parentWorldNodeId 找祖先，不新增任何数据库查询或持久化缓存；改名、移动、改父节点与分类随 Controller 刷新自然反映。现有 resolver 逐级在内存列表查找，复杂度随节点量和路径深度增长，当前不扩展为全局索引重构。

不修改 Category grouping、focus、候选去重、开始/继续、paused/waiting、Planning workspace 目标与返回、Home Root、Temporal、Today 或任何业务逻辑。schema 24、Sync protocol 11 不变。

## 验证

新增 Android 360px / Windows 1400px、1.3 倍字体测试：七层祖先及长标题、无当前节点与分类重复、同名真实祖先保留、顶层无空树、无步骤祖先仍可见、无交互、改名、移动、分类改名后路径更新。原真实 SQLite Home 测试补充标题→祖先→行动项顺序，继续验证浏览不写业务表、canonical Planning 返回与执行流程；Planning 原祖先展示回归保留。

已使用本机中文字体生成并检查双平台测试截图（.debug_backups/home_ancestry_qa/），深层缩进与长名称换行正常。截图为自动测试场景，非真机截图。默认自动测试不依赖本机字体，只有设置 JAX_ANCESTRY_QA_DIR / JAX_ANCESTRY_QA_FONT 才生成截图。

2026-09-15：完整 Flutter 测试 485/485 通过，dart analyze lib test 无问题，git diff --check 通过，Windows debug 与 Android debug 构建成功。日志见 .debug_backups/home_ancestry_full.log、home_ancestry_windows_build.log、home_ancestry_android_build.log。随后已获授权安装真机，记录见下；未通过修改真实执行事项测试功能。


Android debug APK SHA256：`8084895f577e988cabf9fa9acdfe21136ae153ba33828a293b974a6f515d1118`。


## 真机安装记录

Private device rollout evidence omitted from this historical version.

