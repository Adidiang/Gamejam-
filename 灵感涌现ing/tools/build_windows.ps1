param(
    [Parameter(Mandatory = $true)][string]$EnginePath,
    [string]$TemplatePath,
    [string]$OutputDirectory,
    [switch]$RunTests
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) { throw 'EnginePath must point to Godot 4.7.2.' }
$engine = (Resolve-Path -LiteralPath $EnginePath).Path
$console = $engine -replace '\.exe$', '_console.exe'
if ($engine -match '_console\.exe$' -or -not (Test-Path -LiteralPath $console -PathType Leaf)) { $console = $engine }
if ($TemplatePath -and -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) { throw 'TemplatePath must point to windows_release_x86_64.exe.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'builds\windows' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$buildId = 'Inspiration-ing-Windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$packageDir = Join-Path $outputRoot $buildId
New-Item -ItemType Directory -Path $packageDir | Out-Null
$qa = Join-Path $projectRoot 'qa'
New-Item -ItemType Directory -Path $qa -Force | Out-Null
if ($RunTests) {
    & (Join-Path $PSScriptRoot 'launch.ps1') -Tests -EnginePath $engine
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed; no release was exported.' }
}

$presetPath = Join-Path $projectRoot 'export_presets.cfg'
$originalPreset = [System.IO.File]::ReadAllBytes($presetPath)
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    if ($TemplatePath) {
        $template = (Resolve-Path -LiteralPath $TemplatePath).Path.Replace('\', '/')
        $preset = [System.IO.File]::ReadAllText($presetPath)
        $preset = $preset.Replace('custom_template/release=""', ('custom_template/release="' + $template + '"'))
        [System.IO.File]::WriteAllText($presetPath, $preset, $utf8)
    }
    & $console --quiet --headless --path $projectRoot --import --log-file (Join-Path $qa 'export_import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Project import failed.' }
    $exeName = '灵感涌现ing.exe'
    $outputExe = Join-Path $packageDir $exeName
    & $console --headless --path $projectRoot --export-release 'Windows Desktop' $outputExe --log-file (Join-Path $qa 'export_windows.log')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputExe -PathType Leaf)) { throw 'Windows release export failed.' }
} finally {
    [System.IO.File]::WriteAllBytes($presetPath, $originalPreset)
}

# Start the actual Release executable from its own directory, with no editor or
# source-project path. This catches missing packed resources and startup errors.
$bootLog = Join-Path $qa 'windows_release_boot.log'
$bootStdout = Join-Path $qa 'windows_release_stdout.log'
$bootStderr = Join-Path $qa 'windows_release_stderr.log'
$bootArgs = @('--headless', '--quit-after', '10', '--verbose', '--log-file', ('"' + $bootLog + '"'))
$gameProcess = New-Object System.Diagnostics.Process
$gameProcess.StartInfo.FileName = $outputExe
$gameProcess.StartInfo.Arguments = $bootArgs -join ' '
$gameProcess.StartInfo.WorkingDirectory = $packageDir
$gameProcess.StartInfo.UseShellExecute = $false
$gameProcess.StartInfo.CreateNoWindow = $true
$gameProcess.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$gameProcess.StartInfo.RedirectStandardOutput = $true
$gameProcess.StartInfo.RedirectStandardError = $true
try {
    if (-not $gameProcess.Start()) { throw 'Could not start exported game.' }
    $stdoutTask = $gameProcess.StandardOutput.ReadToEndAsync()
    $stderrTask = $gameProcess.StandardError.ReadToEndAsync()
    if (-not $gameProcess.WaitForExit(30000)) { $gameProcess.Kill(); throw 'Exported game startup timed out.' }
    $gameProcess.WaitForExit()
    [System.IO.File]::WriteAllText($bootStdout, $stdoutTask.Result, $utf8)
    [System.IO.File]::WriteAllText($bootStderr, $stderrTask.Result, $utf8)
    if ($gameProcess.ExitCode -ne 0) { throw ('Exported game exited with code ' + $gameProcess.ExitCode) }
} finally {
    $gameProcess.Dispose()
}
$bootOutput = @($bootLog, $bootStdout, $bootStderr) | ForEach-Object { if (Test-Path -LiteralPath $_) { Get-Content -LiteralPath $_ -Raw } }
if (($bootOutput -join "`n") -match '(?m)(SCRIPT ERROR:|ERROR:|Failed to load|Parse Error:)') { throw 'Exported game logged a startup error; inspect qa/windows_release_*.log.' }

$instructions = @'
灵感涌现ing - Windows 试玩版

启动：
1. 先完整解压 ZIP 文件。
2. 双击“灵感涌现ing.exe”。无需安装 Godot。
3. 选择两名不同成员，填写作品名并选择类型和题材，开始游戏。

操作：
- 点击成员：查看能力、学习技能、邀约或分配任务。
- 右下角“排期”：拖动分工，点击“下一回合”结算本月。
- 任务与邀约共用每月行动次数；部分技能有例外。
- 十二月工作展示后进入年末评奖，再招募成员并开始下一年。
- Alt+F4 退出。

本包包含：十名成员、三十项技能、六个角色专属任务、手稿/小生物联动和年末评奖。
这是现有开发分支的试玩构建，保留原有玩法；开发调试入口在 Release 构建中关闭。

已知限制：
- 当前没有玩家“存档/继续游戏”入口，退出后进度不会自动保存。
- 三年结束的最终结局尚未接入，第三年后仍会进入下一年。
- 当前仅部分角色配置了立绘，其余角色使用名字和占位区域。
- 中文字体使用 Windows 系统字体。

引擎与第三方许可证见 licenses 文件夹。
'@
[System.IO.File]::WriteAllText((Join-Path $packageDir '先读我.txt'), $instructions, (New-Object System.Text.UTF8Encoding($true)))
$licenseSource = Join-Path $repositoryRoot 'licenses'
if (-not (Test-Path -LiteralPath $licenseSource -PathType Container)) { throw 'Missing bundled engine license texts.' }
Copy-Item -LiteralPath $licenseSource -Destination (Join-Path $packageDir 'licenses') -Recurse
$sourceCommit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$engineVersion = (& $console --version | Out-String).Trim()
$manifest = [ordered]@{
    project = '灵感涌现ing'
    source_commit = $sourceCommit
    source_dirty = [bool](& git -C $repositoryRoot status --porcelain)
    engine = $engineVersion
    build_mode = 'release'
    architecture = 'x86_64'
    embedded_pck = $true
    native_release_boot = 'passed'
    executable_sha256 = (Get-FileHash -LiteralPath $outputExe -Algorithm SHA256).Hash.ToLowerInvariant()
}
[System.IO.File]::WriteAllText((Join-Path $packageDir 'build-info.json'), ($manifest | ConvertTo-Json), $utf8)
$zipPath = Join-Path $outputRoot ($buildId + '.zip')
# Windows PowerShell's Compress-Archive requests an exclusive writable handle
# to source files. ZipFile reads them without that unnecessary lock.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Output ('PACKAGE_DIR=' + $packageDir)
Write-Output ('PACKAGE_ZIP=' + $zipPath)
