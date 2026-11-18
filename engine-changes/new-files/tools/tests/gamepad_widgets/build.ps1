# Скрипт сборки и запуска автономного unit-теста базовых виджетов и витрины (F2.1)
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

$exePath = Join-Path $outDir "GamepadWidgets_test.exe"
$testCpp = Join-Path $testDir "GamepadWidgets_test.cpp"
$widgetsCpp = Join-Path $engineSrc "GamepadWidgets.cpp"
$modalCpp = Join-Path $engineSrc "GamepadModalStack.cpp"
$focusCpp = Join-Path $engineSrc "GamepadFocusGraph.cpp"

$cmd = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c++17 /EHsc /W4 /O2 /utf-8 /I`"$engineSrc`" `"$testCpp`" `"$widgetsCpp`" `"$modalCpp`" `"$focusCpp`" /Fe:`"$exePath`" /Fo:`"$outDir\\`""
Write-Host "[F2.1 Test Build] Compiling GamepadWidgets_test.exe..."
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "Ошибка компиляции GamepadWidgets_test.exe (код $LASTEXITCODE)"
}

Write-Host "[F2.1 Test Run] Running $exePath..."
& $exePath
if ($LASTEXITCODE -ne 0) {
    throw "Unit-тесты F2.1 завершились с ошибкой (код $LASTEXITCODE)"
}
Write-Host "[F2.1 Test Success] Все тесты успешно пройдены."
