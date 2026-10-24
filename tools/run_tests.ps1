# Run tests with Godot
$godot = $env:GODOT
if (-not $godot) {
    $candidate = "C:\Users\yukin\Documents\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
    if (Test-Path $candidate) {
        $godot = $candidate
    } else {
        $godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
    }
}

if (-not $godot) {
    Write-Error "Godot executable not found. Please set `$env:GODOT or add godot to PATH."
    exit 1
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Write-Host "Running Godot tests using: $godot"
& $godot --headless --path "$projectRoot" -s res://tests/run_tests.gd $args
exit $LASTEXITCODE
