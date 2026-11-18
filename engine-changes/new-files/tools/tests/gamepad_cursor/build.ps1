$ErrorActionPreference = 'Stop'
[System.Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
$currentProc = [System.Diagnostics.Process]::GetCurrentProcess()
$currentProc.PriorityClass = 'BelowNormal'

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = if (Test-Path $vsWhere) { & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
if (-not $vsPath) { $vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools" }
$vsDevCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) { throw "VsDevCmd.bat not found: $vsDevCmd" }
$testDir = $PSScriptRoot
$outDir = Join-Path $testDir "bin"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$exePath = Join-Path $outDir "GamepadCursor_test.exe"
$testCpp = Join-Path $testDir "GamepadCursor_test.cpp"

$cmd = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c++17 /EHsc /W4 /O2 /utf-8 `"$testCpp`" /Fe:`"$exePath`" /Fo:`"$outDir\\`""
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}
& $exePath
exit $LASTEXITCODE
