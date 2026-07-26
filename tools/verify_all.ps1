# HearBloom one-command verification (Windows / PowerShell).
#
#   pwsh tools/verify_all.ps1
#
# Runs the full verification suite: backend pytest + self-test, the headless
# Dart harnesses, the Flutter analyzer and the Flutter tests. Exits non-zero if
# any step fails.
#
# Toolchain: uses `dart` / `flutter` on PATH by default. Override with the
# HEARBLOOM_DART / HEARBLOOM_FLUTTER environment variables (full path to the
# executables) if they are not on PATH.

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps/flutter_app'
$dart = if ($env:HEARBLOOM_DART) { $env:HEARBLOOM_DART } else { 'dart' }
$flutter = if ($env:HEARBLOOM_FLUTTER) { $env:HEARBLOOM_FLUTTER } else { 'flutter' }
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

$failures = @()

function Step($name, [scriptblock]$body) {
  Write-Host "`n=== $name ===" -ForegroundColor Cyan
  & $body
  if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED: $name" -ForegroundColor Red
    $script:failures += $name
  }
}

Push-Location $repoRoot
try {
  Step 'pytest (backend)' { python -m pytest -q }
  Step 'self-test' { python tests/run_selftest.py }

  $harnesses = @('catalog','safety','engine','stage','persistence','results',
                 'recommendation','audio','gap','modulation','sequence','mci','pitch','rate','speech','openset','interval','chord','closed','battery','timbre','identification','dichotic','fatigue','asr','norms','psychometrics','diagnostics','psychoacoustics','tier3')
  foreach ($h in $harnesses) {
    Step "dart harness: $h" {
      & $dart run "apps/flutter_app/tool/verify/${h}_harness.dart"
    }
  }

  Step 'dart analyze (lib + test)' {
    Push-Location $appDir
    & $dart analyze lib test
    $code = $LASTEXITCODE
    Pop-Location
    $global:LASTEXITCODE = $code
  }

  Step 'flutter test' {
    Push-Location $appDir
    & $flutter test
    $code = $LASTEXITCODE
    Pop-Location
    $global:LASTEXITCODE = $code
  }
}
finally {
  Pop-Location
}

Write-Host ''
if ($failures.Count -eq 0) {
  Write-Host 'ALL VERIFICATION STEPS PASSED' -ForegroundColor Green
  exit 0
} else {
  Write-Host ("FAILED STEPS: " + ($failures -join ', ')) -ForegroundColor Red
  exit 1
}
