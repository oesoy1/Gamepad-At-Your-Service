# Скрипт сборки и запуска автономного unit-теста стека модальных окон и прокрутки на паузе (F1.2)
$ErrorActionPreference = 'Stop'

# Ограничиваем приоритет процесса согласно AGENTS.md
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
    throw "VsDevCmd.bat не найден: $vsDevCmd"
}
$testDir = $PSScriptRoot
$engineSrc = Resolve-Path (Join-Path $testDir "..\..\..\src\xrGame")
$outDir = Join-Path $testDir "bin"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$exePath = Join-Path $outDir "GamepadModal_test.exe"
$testCpp = Join-Path $testDir "GamepadModal_test.cpp"
$modalCpp = Join-Path $engineSrc "GamepadModalStack.cpp"
$focusCpp = Join-Path $engineSrc "GamepadFocusGraph.cpp"

$cmd = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c++17 /EHsc /W4 /O2 /utf-8 /I`"$engineSrc`" `"$testCpp`" `"$modalCpp`" `"$focusCpp`" /Fe:`"$exePath`" /Fo:`"$outDir\\`""
Write-Host "[F1.2 Test Build] Compiling GamepadModal_test.exe..."
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "Ошибка компиляции GamepadModal_test.exe (код $LASTEXITCODE)"
}

Write-Host "[F1.2 Test Run] Running $exePath..."
& $exePath
if ($LASTEXITCODE -ne 0) {
    throw "Unit-тесты завершились с ошибкой (код $LASTEXITCODE)"
}
Write-Host "[F1.2 Test Success] Все тесты успешно пройдены."