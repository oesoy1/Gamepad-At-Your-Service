$ErrorActionPreference = 'Stop'

[System.Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
$currentProc = [System.Diagnostics.Process]::GetCurrentProcess()
$currentProc.PriorityClass = 'BelowNormal'

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = if (Test-Path $vsWhere) { & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
if (-not $vsPath) {
    $vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
}

$vsDevCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) {
    throw "VsDevCmd.bat not found: $vsDevCmd"
}
$testDir = $PSScriptRoot
$engineSrc = Resolve-Path (Join-Path $testDir "..\..\..\src\xrGame")
$outDir = Join-Path $testDir "bin"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$exePath = Join-Path $outDir "GamepadTxn_test.exe"
$testCpp = Join-Path $testDir "GamepadTxn_test.cpp"
$txnCpp  = Join-Path $engineSrc "GamepadTxnDispatcher.cpp"
$focCpp  = Join-Path $engineSrc "GamepadFocusGraph.cpp"

$cmd = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c++17 /EHsc /W4 /O2 /utf-8 /I`"$engineSrc`" `"$testCpp`" `"$txnCpp`" `"$focCpp`" /Fe:`"$exePath`" /Fo:`"$outDir\\`""
Write-Host "[F4.1 Test Build] Compiling GamepadTxn_test.exe..."
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile GamepadTxn_test.exe (exit code $LASTEXITCODE)"
}

Write-Host "[F4.1 Test Run] Running $exePath..."
& $exePath
if ($LASTEXITCODE -ne 0) {
    throw "Unit tests failed (exit code $LASTEXITCODE)"
}
Write-Host "[F4.1 Test Success] All F4.1 transaction dispatcher tests passed."
