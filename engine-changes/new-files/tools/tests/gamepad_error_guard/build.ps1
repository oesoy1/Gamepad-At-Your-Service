# S3: build and run the GamepadErrorGuard unit test (no game). ASCII only.
# Single cl.exe process, BelowNormal priority, output in _build\tests\gamepad_error_guard.
param([switch]$NoRun)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$out = Join-Path $root '_build\tests\gamepad_error_guard'
New-Item -ItemType Directory -Force $out | Out-Null
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = if (Test-Path $vsWhere) { & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
if (-not $vsPath) { $vsPath = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools' }
$vsDevCmd = Join-Path $vsPath 'Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path $vsDevCmd)) { throw "VsDevCmd.bat not found: $vsDevCmd" }
$src1 = Join-Path $root 'src\xrEngine\GamepadErrorGuard.cpp'
$src2 = Join-Path $PSScriptRoot 'GamepadErrorGuard_test.cpp'
$bat = Join-Path $out 'build.bat'
Set-Content -Encoding ASCII $bat @(
  '@echo off',
  'set VSLANG=1033',
  "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul || exit /b 2",
  "cl /nologo /utf-8 /std:c++17 /EHsc /W4 /WX /O2 /fp:precise /Fo`"$out\\`" /Fe`"$out\GamepadErrorGuard_test.exe`" `"$src1`" `"$src2`""
)
$p = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -PassThru -RedirectStandardOutput "$out\build.log"
$null = $p.Handle
try { $p.PriorityClass = 'BelowNormal' } catch {}
$p.WaitForExit()
Get-Content "$out\build.log"
if ($p.ExitCode -ne 0) { Write-Host "BUILD FAILED exit=$($p.ExitCode)"; exit $p.ExitCode }
if ($NoRun) { exit 0 }
& "$out\GamepadErrorGuard_test.exe" "$out\tmp" | Tee-Object "$out\test-output.txt"
exit $LASTEXITCODE
