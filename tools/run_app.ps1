# HearBloom one-command launcher (Windows / PowerShell).
#
#   pwsh tools/run_app.ps1            # build (release) + serve on :8080
#   pwsh tools/run_app.ps1 -Port 9000 # choose a port
#   pwsh tools/run_app.ps1 -NoBuild   # serve the existing build immediately
#
# Set $env:HEARBLOOM_FLUTTER to the flutter executable if it is not on PATH.
# This runs the research web build locally. It is NOT a medical device.
[CmdletBinding()]
param(
  [int]$Port = 8080,
  [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
$flutter = if ($env:HEARBLOOM_FLUTTER) { $env:HEARBLOOM_FLUTTER } else { 'flutter' }
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'apps\flutter_app'
Push-Location $app
try {
  if (-not $NoBuild) {
    Write-Host '==> Building HearBloom web (release)...' -ForegroundColor Cyan
    & $flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
  }
  $web = Join-Path $app 'build\web'
  if (-not (Test-Path (Join-Path $web 'index.html'))) {
    throw "No web build found at $web. Re-run without -NoBuild."
  }
  # Free the port if something is already listening.
  Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
  $py = Get-Command py -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
  if (-not $py) { throw 'Python not found (needed to serve the static web build).' }
  Write-Host ''
  Write-Host "==> HearBloom is live at http://127.0.0.1:$Port" -ForegroundColor Green
  Write-Host '    Research build - not a medical device, no diagnostic claims.'
  Write-Host '    Press Ctrl+C to stop.' -ForegroundColor DarkGray
  Write-Host ''
  & $py.Source -m http.server $Port -b 127.0.0.1 --directory $web
} finally {
  Pop-Location
}
