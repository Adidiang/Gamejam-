param([switch]$Editor, [switch]$Tests, [string]$EnginePath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineCandidates = @(
    $EnginePath,
    $env:GODOT_BIN,
    'D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe',
    'F:\GamejamWithWu\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe',
    'F:\gamejam\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
)
$enginePath = $engineCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $enginePath) {
    $engineCommand = Get-Command godot, godot4 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($engineCommand) { $enginePath = $engineCommand.Source }
}
if (-not $enginePath) { throw 'Godot was not found. Pass -EnginePath, set GODOT_BIN, or import project.godot with Godot 4.7.2.' }
$enginePath = (Resolve-Path -LiteralPath $enginePath).Path
$arguments = @('--path', ('"' + $projectRoot + '"'))
if ($Tests) {
    $consoleEngine = $enginePath -replace '\.exe$', '_console.exe'
    if ($enginePath -match '_console\.exe$' -or -not (Test-Path -LiteralPath $consoleEngine -PathType Leaf)) { $consoleEngine = $enginePath }
    $testOutput = Join-Path $projectRoot 'qa'
    New-Item -ItemType Directory -Path $testOutput -Force | Out-Null
    & $consoleEngine --quiet --headless --path $projectRoot --import --log-file (Join-Path $testOutput 'import.log')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    foreach ($testName in @('test_character_skills', 'test_character_ui', 'test_starting_roster', 'test_recruitment', 'test_skills', 'test_sheep_skills', 'test_skill_ui', 'test_duty_assignment_ui', 'test_main_hud', 'test_debug_tools', 'test_monthly_work_ui', 'test_task_assignment', 'test_invite', 'test_game_selection', 'test_annual_award', 'test_text_confirm', 'test_character_table', 'test_game')) {
        & $consoleEngine --headless --path $projectRoot --script "res://tests/$testName.gd" --log-file (Join-Path $testOutput "$testName.log")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    exit 0
}
if ($Editor) { $arguments += '--editor' }
# This is the interactive game/editor the player explicitly launches.
Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory $projectRoot
