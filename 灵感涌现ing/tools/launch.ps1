param([switch]$Editor, [switch]$Tests)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineCandidates = @(
    'D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe',
    'F:\GamejamWithWu\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe',
    'F:\gamejam\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
)
$enginePath = $engineCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $enginePath) { throw 'Godot was not found. Import project.godot with Godot 4.7, or update tools/launch.ps1.' }
$arguments = @('--path', ('"' + $projectRoot + '"'))
if ($Tests) {
    $consoleEngine = $enginePath -replace '\.exe$', '_console.exe'
    $testOutput = Join-Path $projectRoot 'qa'
    New-Item -ItemType Directory -Path $testOutput -Force | Out-Null
    foreach ($testName in @('test_starting_roster', 'test_recruitment', 'test_skills', 'test_sheep_skills', 'test_skill_ui', 'test_duty_assignment_ui', 'test_main_hud', 'test_debug_tools', 'test_monthly_work_ui', 'test_task_assignment', 'test_invite', 'test_game_selection', 'test_annual_award', 'test_text_confirm', 'test_character_table', 'test_game')) {
        & $consoleEngine --headless --path $projectRoot --script "res://tests/$testName.gd" --log-file (Join-Path $testOutput "$testName.log")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    exit 0
}
if ($Editor) { $arguments += '--editor' }
# This is the interactive game/editor the player explicitly launches.
Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory $projectRoot
