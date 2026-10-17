# Windows 试玩构建

适用于 Godot 4.7.2 / Windows x86_64。试玩包内嵌游戏资源，玩家完整解压 ZIP 后双击 `灵感涌现ing.exe`，无需安装引擎。

## 源码与范围

2026-10-17 核验时，`main` 的 `4a6289e` 尚未包含十人技能实现；十人三十技能来自 `codex/ten-character-skills` 的 `6ca4afe`。试玩以此分支为基础，不重做队友已经实现的角色技能。构建与验证改动保存在本地分支 `codex/verify-ten-character-integration`，没有推送或合并到团队仓库。

现有功能：两名初始成员选择、年度立项、岗位排期、任务／邀约、技能学习、月结、评奖、招募和跨年。开发调试功能在 Release 模板中由 `OS.is_debug_build()` 自动关闭。

## 构建

准备 Godot 4.7.2 Windows 编辑器和对应版本的导出模板。在仓库的 `灵感涌现ing` 目录运行：

```powershell
& .\tools\build_windows.ps1 -EnginePath 'C:\Godot\Godot_v4.7.2-stable_win64.exe' -RunTests
```

如果没有安装整套模板，可额外传入 `-TemplatePath 'C:\Godot\windows_release_x86_64.exe'`。该路径仅在构建过程中写入预设，结束后恢复，不应提交个人路径。`-OutputDirectory` 可覆盖默认的 `builds\windows` 输出位置。

脚本先导入资源，按需运行 18 组回归测试，导出 Release，直接启动导出的 EXE 检查资源与错误日志，再生成说明、引擎许可证、含源码状态及 EXE SHA-256 的 `build-info.json` 和 ZIP。`export_presets.cfg` 包含运行时 JSON，排除测试、开发脚本、策划文档、日志和存档。`application/modify_resources=false` 避免依赖本机资源编辑工具；目前使用引擎默认的 EXE 图标与版本信息。

## 验证

`tools/launch.ps1 -Tests` 运行 18 组测试，日志位于 `qa/`。另外可从导出目录用编辑器加载打包资源，验证选人、立项、邀约、十二次月结、评奖、招募和第二年立项：

```powershell
& '<Godot 控制台 exe>' --headless --main-pack '<导出 exe>' --script '<工程绝对路径>\tools\verify_windows.gd' -- --report-path '<报告绝对路径>.json'
```

报告中的 `verification_mode` 区分编辑器加载导出资源和原生 Release 运行。编辑器路径会在测试进程中关闭调试功能，不修改源码；不能将它记为原生 Release 完整流程验收。部分模板可能禁用外部脚本覆盖，这时保留独立 EXE 的启动和画面验证。图形运行此脚本会另外保存游戏自身渲染的界面截图。完整流程验证需等待工作展示动画，可用 `--time-scale 10` 加速。

## 试玩限制

- 没有玩家存档／继续入口；退出后丢失本次进度。
- 三年后的最终结局未接入，第三年后仍进入下一年。
- 只有 a、b、c 配有立绘，另外七人尚待美术资源；加入文本也有占位文案。
- 中文使用 Windows 系统字体；当前机器的启动验证不代表所有显卡和系统配置均已验证。

后续验收优先完成一次真实的 36 个月试玩，确认招募、技能搭配和资源节奏，再确定三年收尾与美术接入。存档入口需要先选择保存时机和继续流程；本次构建保留已有玩法，不代替策划决定。
