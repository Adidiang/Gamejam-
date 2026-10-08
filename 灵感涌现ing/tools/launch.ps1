param([switch]$Editor, [switch]$Tests)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineCandidates = @(
    'F:\GamejamWithWu\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe',
    'F:\gamejam\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
)
$enginePath = $engineCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $enginePath) { throw 'Godot was not found. Import project.godot with Godot 4.7, or update tools/launch.ps1.' }
$arguments = @('--path', ('"' + $projectRoot + '"'))
if ($Tests) {
    $consoleEngine = $enginePath -replace '\.exe$', '_console.exe'
    & $consoleEngine --headless --path $projectRoot --script res://tests/test_game.gd
    exit $LASTEXITCODE
}
if ($Editor) { $arguments += '--editor' }
# This is the interactive game/editor the player explicitly launches.
Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory $projectRoot
