# Run dedicated headless server for cl.k2
param(
    [int]$Port = 8910,
    [int]$MaxPlayers = 16,
    [int]$Seed = 42
)

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
Write-Host "Starting cl.k2 Dedicated Server on port $Port (seed: $Seed, max-players: $MaxPlayers)..."
& $godot --headless --path "$projectRoot" -- --server --port=$Port --max-players=$MaxPlayers --seed=$Seed $args
