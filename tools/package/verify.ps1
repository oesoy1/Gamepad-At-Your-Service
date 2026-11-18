<#
.SYNOPSIS
    Gamepad At Your Service — Read-Only Installation & Package Verifier (I1.2, D64).
    СТРОГО ТОЛЬКО ЧТЕНИЕ / STRICTLY READ-ONLY: never modifies Anomaly, MO2, or user files.

.DESCRIPTION
    Verifies either:
      A) An installed game (Anomaly\bin + MO2\mods / modlist.txt + appdata\gamepad\profile.ltx,
         or standalone Anomaly\gamedata when -Mo2Root is omitted) against manifest.sha256.json.
         When launched from <GAMMA>\mods\<ModName>\tools\verify.ps1 with no arguments,
         auto-detects -Mo2Root and -AnomalyRoot from ..\..\ModOrganizer.ini.
      B) A staged / unpacked release package (-PackageRoot) against manifest.sha256.json,
         encoding rules (Windows-1251 without BOM), PE import table, and clean-room exclusions.

    Exit codes:
      0 - PASS (all checks passed)
      2 - WARN (playable, minor recommendations such as missing backup)
      1 - FAIL (missing/corrupted/overwritten file, stock EXE without gamepad support, or bad MO2 order)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AnomalyRoot = "",

    [Parameter(Mandatory = $false)]
    [string]$Mo2Root = "",

    [Parameter(Mandatory = $false)]
    [string]$ProfileName = "",

    [Parameter(Mandatory = $false)]
    [string]$ModName = "GAMMA Gamepad & Tactical UI",

    [Parameter(Mandatory = $false)]
    [string]$PackageRoot = "",

    [Parameter(Mandatory = $false)]
    [string]$ManifestPath = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("both", "ru", "en")]
    [string]$Lang = "both",

    [Parameter(Mandatory = $false)]
    [string]$JsonOut = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Known stock (unmodded) executable SHA-256 hashes (uppercase) to give clear update-overwrite guidance
$KnownStockExeHashes = @{
    "F48B423AB48E2A80E8A741E6AD92608DBF115831678D2F4A53F04D3DBE44AFF7" = "X-Ray Monolith MT 2026.10.11 (stock G.A.M.M.A. AnomalyDX11AVX.exe)"
    "ADE57887F93CA95E9398DA60B374035B50E4C38295B9802A6F89BC33A0394BC"  = "X-Ray Monolith MT 2026.05.15 (stock Stalker_GAMMA AnomalyDX11AVX.exe)"
    "C434471FBFFF5409442847119B07B02B22409F64A2F1FEDFFE802259A118D2AC" = "Stock PBR test AnomalyDX11AVX.exe (without gamepad module)"
    "F4C892E798191C31FD6C4E3EBE5D0157E0047D7E25A2A59D9ED0C54377C9E3BD" = "Stock AnomalyDX11.exe (without gamepad module)"
    "93E2A7D68589488164727A98769A13E77958854BF18B87A5D414BE283EC74281" = "Stock PBR AnomalyDX12.exe (without gamepad module)"
}

$ForbiddenPbrShaderNames = @{
    "hashed_alpha.h"        = $true
    "ssfx_sss.ps"           = $true
    "ssfx_sss_ext.ps"       = $true
    "upscaler_reactive.ps"  = $true
    "screenspace_shadows.h" = $true
}

$Results = New-Object System.Collections.Generic.List[object]

function Format-Bilingual {
    param([string]$Ru, [string]$En)
    switch ($Lang) {
        "ru"   { return $Ru }
        "en"   { return $En }
        default {
            if ($Ru -eq $En -or [string]::IsNullOrWhiteSpace($En)) { return $Ru }
            return "$Ru`n          EN: $En"
        }
    }
}

function Add-CheckResult {
    param(
        [ValidateSet("PASS", "WARN", "FAIL")]
        [string]$Status,
        [string]$Code,
        [string]$TitleRu,
        [string]$TitleEn,
        [string]$DetailRu = "",
        [string]$DetailEn = "",
        [string]$FixRu = "",
        [string]$FixEn = ""
    )
    $Results.Add([PSCustomObject]@{
        Status   = $Status
        Code     = $Code
        TitleRu  = $TitleRu
        TitleEn  = $TitleEn
        DetailRu = $DetailRu
        DetailEn = $DetailEn
        FixRu    = $FixRu
        FixEn    = $FixEn
    })
    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
    }
    $title = switch ($Lang) {
        "ru" { $TitleRu }
        "en" { $TitleEn }
        default { "$TitleRu / $TitleEn" }
    }
    Write-Host ("[{0}] ({1}) {2}" -f $Status, $Code, $title) -ForegroundColor $color
    $det = Format-Bilingual -Ru $DetailRu -En $DetailEn
    if (-not [string]::IsNullOrWhiteSpace($det)) {
        Write-Host ("       {0}" -f $det) -ForegroundColor Gray
    }
    if ($Status -ne "PASS") {
        $fix = Format-Bilingual -Ru $FixRu -En $FixEn
        if (-not [string]::IsNullOrWhiteSpace($fix)) {
            Write-Host ("       -> {0}" -f $fix) -ForegroundColor Cyan
        }
    }
}

function Get-PeImportedDlls {
    param([string]$FilePath)
    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $br = New-Object System.IO.BinaryReader($fs)
    try {
        if ($fs.Length -lt 128) { return @() }
        if ($br.ReadUInt16() -ne 0x5A4D) { return @() }
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        if ($peOffset -lt 0 -or ($peOffset + 24) -gt $fs.Length) { return @() }
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { return @() }

        $null = $br.ReadUInt16()
        $numSections = $br.ReadUInt16()
        $fs.Position += 12
        $sizeOfOptHeader = $br.ReadUInt16()
        $null = $br.ReadUInt16()

        $optHeaderStart = $fs.Position
        $magic = $br.ReadUInt16()
        if ($magic -eq 0x20B) {
            $importDirOffset = $optHeaderStart + 112 + 8
        } elseif ($magic -eq 0x10B) {
            $importDirOffset = $optHeaderStart + 96 + 8
        } else {
            return @()
        }

        $fs.Position = $importDirOffset
        $importRva = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        if ($importRva -eq 0) { return @() }

        $sectionsStart = $optHeaderStart + $sizeOfOptHeader
        $sections = @()
        for ($i = 0; $i -lt $numSections; $i++) {
            $fs.Position = $sectionsStart + ($i * 40) + 8
            $vSize = $br.ReadUInt32()
            $vAddr = $br.ReadUInt32()
            $rawSize = $br.ReadUInt32()
            $rawPtr = $br.ReadUInt32()
            $sections += [PSCustomObject]@{
                VirtualAddress = $vAddr
                Span           = [Math]::Max($vSize, $rawSize)
                RawPointer     = $rawPtr
            }
        }

        function Convert-RvaToOffset([uint32]$Rva, $SecList) {
            foreach ($s in $SecList) {
                if ($Rva -ge $s.VirtualAddress -and $Rva -lt ($s.VirtualAddress + $s.Span)) {
                    return ($Rva - $s.VirtualAddress) + $s.RawPointer
                }
            }
            return -1
        }

        $impOffset = Convert-RvaToOffset $importRva $sections
        if ($impOffset -lt 0) { return @() }

        $dllNames = @()
        $idx = 0
        while ($true) {
            $fs.Position = $impOffset + ($idx * 20)
            if (($fs.Position + 20) -gt $fs.Length) { break }
            $origFirstThunk = $br.ReadUInt32()
            $null = $br.ReadUInt32()
            $null = $br.ReadUInt32()
            $nameRva = $br.ReadUInt32()
            $firstThunk = $br.ReadUInt32()
            if ($origFirstThunk -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) { break }

            $nameOff = Convert-RvaToOffset $nameRva $sections
            if ($nameOff -ge 0 -and $nameOff -lt $fs.Length) {
                $fs.Position = $nameOff
                $bytes = New-Object System.Collections.Generic.List[byte]
                while ($fs.Position -lt $fs.Length) {
                    $b = $br.ReadByte()
                    if ($b -eq 0) { break }
                    $bytes.Add($b)
                }
                $dllNames += [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
            }
            $idx++
        }
        return $dllNames
    } finally {
        $br.Close()
        $fs.Close()
    }
}

function Resolve-Mo2GamePath {
    param([string]$Mo2IniPath)
    if (-not (Test-Path -LiteralPath $Mo2IniPath)) { return "" }
    $lines = [System.IO.File]::ReadAllLines($Mo2IniPath, [System.Text.Encoding]::UTF8)
    foreach ($ln in $lines) {
        if ($ln -match "^\s*gamePath\s*=\s*(.+)$") {
            $rawVal = $Matches[1].Trim()
            if ($rawVal -match "^@ByteArray\((.*)\)$") { $rawVal = $Matches[1] }
            $rawVal = $rawVal.Trim('"').Replace("\\", "\").Replace("/", "\")
            if ($rawVal.StartsWith("\\")) {
                $rawVal = "\\" + ($rawVal.Substring(2) -replace "\\{2,}", "\")
            } else {
                $rawVal = $rawVal -replace "\\{2,}", "\"
            }
            $rawVal = $rawVal.TrimEnd("\")
            if ($rawVal -and (Test-Path -LiteralPath (Join-Path $rawVal "bin"))) {
                return $rawVal
            }
        }
    }
    return ""
}

function Resolve-ManifestFile {
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        if (Test-Path -LiteralPath $ManifestPath) { return (Resolve-Path -LiteralPath $ManifestPath).Path }
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
        $cand1 = Join-Path $PackageRoot "manifest.sha256.json"
        if (Test-Path -LiteralPath $cand1) { return (Resolve-Path -LiteralPath $cand1).Path }
        $candSub = Join-Path (Join-Path $PackageRoot $ModName) "manifest.sha256.json"
        if (Test-Path -LiteralPath $candSub) { return (Resolve-Path -LiteralPath $candSub).Path }
    }
    $scriptDir = $PSScriptRoot
    if (-not [string]::IsNullOrWhiteSpace($scriptDir)) {
        $near1 = Join-Path $scriptDir "manifest.sha256.json"
        if (Test-Path -LiteralPath $near1) { return (Resolve-Path -LiteralPath $near1).Path }
        $parentDir = Split-Path -Parent $scriptDir
        if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
            $near2 = Join-Path $parentDir "manifest.sha256.json"
            if (Test-Path -LiteralPath $near2) { return (Resolve-Path -LiteralPath $near2).Path }
        }
    }
    return $null
}

function Test-NoBomEncoding {
    param([string]$FilePath)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return "UTF8_BOM"
    }
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        return "UTF16_BOM"
    }
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 0) { return "NUL_BYTE" }
    }
    return "OK"
}

# Auto-detect MO2 and Anomaly when invoked directly inside <GAMMA>\mods\<ModName>\tools\verify.ps1
if ([string]::IsNullOrWhiteSpace($AnomalyRoot) -and [string]::IsNullOrWhiteSpace($PackageRoot) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $modRootCand = Split-Path -Parent $PSScriptRoot
    $modsParent = if ($modRootCand) { Split-Path -Parent $modRootCand } else { "" }
    $mo2Cand = if ($modsParent) { Split-Path -Parent $modsParent } else { "" }
    if ($mo2Cand -and (Test-Path -LiteralPath (Join-Path $mo2Cand "ModOrganizer.ini"))) {
        $detectedAnomaly = Resolve-Mo2GamePath -Mo2IniPath (Join-Path $mo2Cand "ModOrganizer.ini")
        if ($detectedAnomaly) {
            $AnomalyRoot = $detectedAnomaly
            if ([string]::IsNullOrWhiteSpace($Mo2Root)) { $Mo2Root = $mo2Cand }
            if ($ModName -eq "GAMMA Gamepad & Tactical UI" -and $modRootCand) {
                $ModName = Split-Path -Leaf $modRootCand
            }
        }
    }
}

Write-Host "========================================================================" -ForegroundColor White
Write-Host " GAMEPAD AT YOUR SERVICE — ПРОВЕРКА УСТАНОВКИ / INSTALLATION VERIFIER" -ForegroundColor White
Write-Host " Режим: ТОЛЬКО ЧТЕНИЕ (Read-Only) — файлы игры не изменяются" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor White

$resolvedManifest = Resolve-ManifestFile
$manifest = $null
if ($null -ne $resolvedManifest) {
    $manifestRaw = [System.IO.File]::ReadAllText($resolvedManifest, [System.Text.Encoding]::UTF8)
    $manifest = $manifestRaw | ConvertFrom-Json
    Add-CheckResult -Status "PASS" -Code "MANIFEST_LOADED" `
        -TitleRu "Манифест контрольных сумм загружен" `
        -TitleEn "SHA-256 manifest loaded" `
        -DetailRu ("Версия {0}, цель: {1} ({2})" -f $manifest.version, $manifest.target, $resolvedManifest) `
        -DetailEn ("Version {0}, target: {1} ({2})" -f $manifest.version, $manifest.target, $resolvedManifest)
}

# ==============================================================================
# MODE A: Staged / Unpacked Release Package Audit (-PackageRoot)
# ==============================================================================
if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
    $resolvedPkgRoot = $PackageRoot
    if ((Test-Path -LiteralPath $PackageRoot) -and -not (Test-Path -LiteralPath (Join-Path $PackageRoot "manifest.sha256.json"))) {
        $subPkg = Join-Path $PackageRoot $ModName
        if (Test-Path -LiteralPath (Join-Path $subPkg "manifest.sha256.json")) {
            $resolvedPkgRoot = $subPkg
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPkgRoot)) {
        Add-CheckResult -Status "FAIL" -Code "PKG_ROOT_MISSING" `
            -TitleRu "Папка пакета не найдена" `
            -TitleEn "Package folder not found" `
            -DetailRu $resolvedPkgRoot -DetailEn $resolvedPkgRoot `
            -FixRu "Укажите верный путь в -PackageRoot." -FixEn "Pass a valid path to -PackageRoot."
    } elseif ($null -eq $manifest) {
        Add-CheckResult -Status "FAIL" -Code "PKG_MANIFEST_MISSING" `
            -TitleRu "В пакете отсутствует manifest.sha256.json" `
            -TitleEn "manifest.sha256.json is missing from package" `
            -FixRu "Пересоберите архив через build_release.ps1." -FixEn "Rebuild package via build_release.ps1."
    } else {
        # 1. Verify required MO2-ready package structure
        $reqDirs = @("gamedata", "engine_files", "tools", "THIRD_PARTY")
        foreach ($d in $reqDirs) {
            $dp = Join-Path $resolvedPkgRoot $d
            if (-not (Test-Path -LiteralPath $dp)) {
                Add-CheckResult -Status "FAIL" -Code "PKG_DIR_MISSING" `
                    -TitleRu ("Отсутствует обязательная папка: {0}" -f $d) `
                    -TitleEn ("Missing required package folder: {0}" -f $d) `
                    -FixRu "Пересоберите релизный архив." -FixEn "Rebuild the release archive."
            }
        }
        $reqFiles = @(
            "meta.ini",
            "engine_files\engine_helper.ps1",
            "tools\verify.ps1",
            "Установить_движок.cmd",
            "Вернуть_оригинал.cmd",
            "Install_Engine.cmd",
            "Restore_Original.cmd",
            "README-RU.txt",
            "README-EN.txt",
            "THIRD-PARTY-NOTICES.txt",
            "SHA256SUMS.txt"
        )
        foreach ($rf in $reqFiles) {
            $fp = Join-Path $resolvedPkgRoot $rf
            if (-not (Test-Path -LiteralPath $fp)) {
                Add-CheckResult -Status "FAIL" -Code "PKG_FILE_MISSING" `
                    -TitleRu ("Отсутствует обязательный файл: {0}" -f $rf) `
                    -TitleEn ("Missing required package file: {0}" -f $rf) `
                    -FixRu "Пересоберите релизный архив." -FixEn "Rebuild the release archive."
            }
        }
        if (Test-Path -LiteralPath (Join-Path $resolvedPkgRoot "bin")) {
            Add-CheckResult -Status "FAIL" -Code "PKG_FORBIDDEN_BIN_DIR" `
                -TitleRu "В корне мода обнаружена папка bin\ (должна называться engine_files\)" `
                -TitleEn "Found bin\ directory inside MO2 mod root (must be engine_files\)" `
                -FixRu "Переместите файлы движка в engine_files\." -FixEn "Place engine binaries inside engine_files\."
        }

        # 2. Verify every file in manifest.sha256.json
        $hashOk = 0
        $hashBad = @()
        foreach ($entry in $manifest.files) {
            $rel = ($entry.path -replace "/", "\")
            $full = Join-Path $resolvedPkgRoot $rel
            if (-not (Test-Path -LiteralPath $full)) {
                $hashBad += "MISSING: $rel"
                continue
            }
            $actualHash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actualHash -ne $entry.sha256.ToUpperInvariant()) {
                $hashBad += "HASH_MISMATCH: $rel (expected $($entry.sha256), got $actualHash)"
                continue
            }
            $hashOk++
        }
        if ($hashBad.Count -eq 0) {
            Add-CheckResult -Status "PASS" -Code "PKG_HASHES_OK" `
                -TitleRu "Все файлы пакета совпадают с манифестом SHA-256" `
                -TitleEn "All package files match SHA-256 manifest" `
                -DetailRu ("Проверено файлов: {0}" -f $hashOk) `
                -DetailEn ("Verified files: {0}" -f $hashOk)
        } else {
            Add-CheckResult -Status "FAIL" -Code "PKG_HASHES_FAIL" `
                -TitleRu "Нарушена целостность файлов пакета" `
                -TitleEn "Package file integrity check failed" `
                -DetailRu ($hashBad[0..([Math]::Min(4, $hashBad.Count - 1))] -join "; ") `
                -DetailEn ($hashBad[0..([Math]::Min(4, $hashBad.Count - 1))] -join "; ") `
                -FixRu "Скачайте или соберите архив заново." -FixEn "Re-download or rebuild the archive."
        }

        # 3. Verify gamedata\ cleanliness & encodings
        $gdDir = Join-Path $resolvedPkgRoot "gamedata"
        if (Test-Path -LiteralPath $gdDir) {
            $allowedDlssShaders = @{}
            if ($manifest.target -in @("gamma-monolith-dlss", "pbr-dx12-optional")) {
                foreach ($me in $manifest.files) {
                    if ($me.category -eq "dlss_overlay_gamedata" -and ($me.path -replace "\\", "/") -match "(?i)^gamedata/shaders/") {
                        $allowedDlssShaders[($me.path -replace "\\", "/").ToLowerInvariant()] = $true
                    }
                }
            }

            $forbiddenInGd = Get-ChildItem -LiteralPath $gdDir -Recurse -File | Where-Object {
                $relGd = $_.FullName.Substring($resolvedPkgRoot.Length + 1) -replace "\\", "/"
                $relGdLower = $relGd.ToLowerInvariant()
                $isBadExt = $_.Extension -in @(".dll", ".exe", ".pdb", ".lib", ".exp", ".bak", ".orig")
                $isDebug = $_.Name -match "^(zz_gp_perf_|zz_gp_batch|qa_autotest_|gp_testkit|ui_gp_testkit)"
                $isForbiddenShader = $false
                if ($relGdLower -match "^gamedata/shaders/") {
                    if ($ForbiddenPbrShaderNames.ContainsKey($_.Name.ToLowerInvariant())) {
                        $isForbiddenShader = $true
                    } elseif (-not $allowedDlssShaders.ContainsKey($relGdLower)) {
                        $isForbiddenShader = $true
                    }
                }
                $isBadExt -or $isDebug -or $isForbiddenShader
            }
            if (@($forbiddenInGd).Count -eq 0) {
                Add-CheckResult -Status "PASS" -Code "PKG_MOD_CLEAN" `
                    -TitleRu "В папке gamedata нет отладочных, временных и запрещённых файлов" `
                    -TitleEn "No debug, temporary, forbidden shader, or binary files inside gamedata"
            } else {
                $names = ($forbiddenInGd | ForEach-Object { $_.Name }) -join ", "
                Add-CheckResult -Status "FAIL" -Code "PKG_MOD_FORBIDDEN" `
                    -TitleRu "В папке gamedata найдены запрещённые/отладочные файлы" `
                    -TitleEn "Forbidden or debug files found inside gamedata" `
                    -DetailRu $names -DetailEn $names `
                    -FixRu "Исключите их в build_release.ps1." -FixEn "Exclude them in build_release.ps1."
            }

            $badEnc = @()
            $textFiles = @(Get-ChildItem -LiteralPath $gdDir -Recurse -File | Where-Object { $_.Extension -in @(".script", ".ltx", ".xml") })
            foreach ($tf in $textFiles) {
                $encSt = Test-NoBomEncoding -FilePath $tf.FullName
                if ($encSt -ne "OK") { $badEnc += "$($tf.Name):$encSt" }
            }
            if ($badEnc.Count -eq 0) {
                Add-CheckResult -Status "PASS" -Code "PKG_ENCODING_OK" `
                    -TitleRu "Все игровые скрипты, конфиги и XML сохранены без BOM (совместимы с X-Ray)" `
                    -TitleEn "All game scripts, configs, and XMLs have clean BOM-free encoding" `
                    -DetailRu ("Проверено файлов: {0}" -f @($textFiles).Count) `
                    -DetailEn ("Checked files: {0}" -f @($textFiles).Count)
            } else {
                Add-CheckResult -Status "FAIL" -Code "PKG_ENCODING_FAIL" `
                    -TitleRu "Найдены игровые файлы с недопустимым BOM или нулевыми байтами" `
                    -TitleEn "Found game text files with forbidden BOM or NUL bytes" `
                    -DetailRu ($badEnc -join ", ") -DetailEn ($badEnc -join ", ") `
                    -FixRu "Перекодируйте в Windows-1251 без BOM." -FixEn "Re-encode as Windows-1251 without BOM."
            }
        }

        # 4. PE import check on packaged EXE(s)
        $exesToCheck = New-Object System.Collections.Generic.List[object]
        $exesToCheck.Add([PSCustomObject]@{ Name = $manifest.engine.exe_name; Path = $manifest.engine.package_path })
        if ($manifest.engine.PSObject.Properties.Name -contains "additional_exes") {
            foreach ($ax in @($manifest.engine.additional_exes)) {
                if ($ax.package_path) {
                    $exesToCheck.Add([PSCustomObject]@{ Name = $ax.exe_name; Path = $ax.package_path })
                }
            }
        }

        foreach ($ex in $exesToCheck) {
            $exeFull = Join-Path $resolvedPkgRoot ($ex.Path -replace "/", "\")
            if (-not (Test-Path -LiteralPath $exeFull)) { continue }
            if ($manifest.engine.is_stub -eq $true) {
                Add-CheckResult -Status "WARN" -Code "PKG_ENGINE_STUB" `
                    -TitleRu "В пакете лежит временная заглушка движка" `
                    -TitleEn "Package contains an engine placeholder stub" `
                    -DetailRu ("Файл: {0} ({1})" -f $ex.Name, $manifest.engine.stub_reason) `
                    -DetailEn ("File: {0} ({1})" -f $ex.Name, $manifest.engine.stub_reason) `
                    -FixRu "Пересоберите пакет без -AllowEngineStub." `
                    -FixEn "Re-run build_release.ps1 without -AllowEngineStub."
            } else {
                $imports = @(Get-PeImportedDlls -FilePath $exeFull)
                $hasSdl3 = @($imports | Where-Object { $_ -ieq "SDL3.dll" }).Count -gt 0
                if ($hasSdl3) {
                    Add-CheckResult -Status "PASS" -Code "PKG_EXE_PE_OK" `
                        -TitleRu ("Исполняемый файл движка {0} проверен (PE x64, импорт SDL3.dll подтверждён)" -f $ex.Name) `
                        -TitleEn ("Engine executable {0} verified (PE x64, SDL3.dll import present)" -f $ex.Name)
                } else {
                    Add-CheckResult -Status "FAIL" -Code "PKG_EXE_NO_SDL3" `
                        -TitleRu ("В файле {0} отсутствует импорт SDL3.dll" -f $ex.Name) `
                        -TitleEn ("Engine executable {0} does not import SDL3.dll" -f $ex.Name) `
                        -FixRu "Укажите собранный с поддержкой геймпада EXE в -EngineExe." `
                        -FixEn "Pass a gamepad-enabled engine executable via -EngineExe."
                }
            }
        }
    }
}

# ==============================================================================
# MODE B: Installed Game Verification (-AnomalyRoot [+ optional -Mo2Root])
# ==============================================================================
if (-not [string]::IsNullOrWhiteSpace($AnomalyRoot)) {
    if (-not (Test-Path -LiteralPath $AnomalyRoot)) {
        Add-CheckResult -Status "FAIL" -Code "ANOMALY_ROOT_MISSING" `
            -TitleRu "Папка Anomaly не найдена" `
            -TitleEn "Anomaly folder not found" `
            -DetailRu $AnomalyRoot -DetailEn $AnomalyRoot `
            -FixRu "Проверьте путь в параметре -AnomalyRoot." `
            -FixEn "Check the -AnomalyRoot path."
    } else {
        $binDir = Join-Path $AnomalyRoot "bin"
        $expectedExeName = if ($null -ne $manifest -and $manifest.engine.exe_name) {
            [string]$manifest.engine.exe_name
        } elseif (Test-Path -LiteralPath (Join-Path $binDir "AnomalyDX12-DLSS.exe")) {
            "AnomalyDX12-DLSS.exe"
        } elseif (Test-Path -LiteralPath (Join-Path $binDir "AnomalyDX11AVX.exe")) {
            "AnomalyDX11AVX.exe"
        } elseif (Test-Path -LiteralPath (Join-Path $binDir "AnomalyDX12.exe")) {
            "AnomalyDX12.exe"
        } else {
            "AnomalyDX11AVX.exe"
        }

        $exePath = Join-Path $binDir $expectedExeName
        $origPath = "$exePath.orig"
        $backupDir = Join-Path $binDir "_gamepad_backup"
        $backupManifestPath = Join-Path $backupDir "backup_manifest.json"
        $sdlPath = Join-Path $binDir "SDL3.dll"

        # 1. Check primary Engine EXE
        if (-not (Test-Path -LiteralPath $exePath)) {
            Add-CheckResult -Status "FAIL" -Code "GAME_EXE_MISSING" `
                -TitleRu ("Не найден файл запуска {0} в Anomaly\bin" -f $expectedExeName) `
                -TitleEn ("Executable {0} not found in Anomaly\bin" -f $expectedExeName) `
                -DetailRu $exePath -DetailEn $exePath `
                -FixRu "Запустите Установить_движок.cmd (или Install_Engine.cmd) внутри папки мода." `
                -FixEn "Run Install_Engine.cmd (or Установить_движок.cmd) inside the mod folder."
        } else {
            $instExeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($KnownStockExeHashes.ContainsKey($instExeHash)) {
                $stockDesc = $KnownStockExeHashes[$instExeHash]
                Add-CheckResult -Status "FAIL" -Code "GAME_EXE_IS_STOCK" `
                    -TitleRu ("В Anomaly\bin стоит обычный {0} без поддержки геймпада" -f $expectedExeName) `
                    -TitleEn ("Anomaly\bin contains stock {0} without gamepad support" -f $expectedExeName) `
                    -DetailRu ("Обнаружен стандартный бинарник: {0}" -f $stockDesc) `
                    -DetailEn ("Detected stock binary: {0}" -f $stockDesc) `
                    -FixRu "Скорее всего, игру обновил G.A.M.M.A. Launcher. Запустите Установить_движок.cmd в папке мода." `
                    -FixEn "G.A.M.M.A. Launcher likely overwrote the EXE. Run Install_Engine.cmd inside the mod folder."
            } elseif ($null -ne $manifest -and $manifest.engine.sha256) {
                $expExeHash = $manifest.engine.sha256.ToUpperInvariant()
                if ($instExeHash -eq $expExeHash) {
                    Add-CheckResult -Status "PASS" -Code "GAME_EXE_HASH_OK" `
                        -TitleRu ("Файл движка {0} полностью совпадает с релизным манифестом" -f $expectedExeName) `
                        -TitleEn ("Engine binary {0} matches the release manifest SHA-256" -f $expectedExeName) `
                        -DetailRu ("SHA-256: {0}" -f $instExeHash) -DetailEn ("SHA-256: {0}" -f $instExeHash)
                } else {
                    Add-CheckResult -Status "FAIL" -Code "GAME_EXE_HASH_MISMATCH" `
                        -TitleRu ("Контрольная сумма {0} не совпадает с версией мода" -f $expectedExeName) `
                        -TitleEn ("{0} checksum does not match this mod package" -f $expectedExeName) `
                        -DetailRu ("Ожидался {0}, установлен {1}" -f $expExeHash.Substring(0, 16), $instExeHash.Substring(0, 16)) `
                        -DetailEn ("Expected {0}, installed {1}" -f $expExeHash.Substring(0, 16), $instExeHash.Substring(0, 16)) `
                        -FixRu "Запустите Установить_движок.cmd внутри папки мода (и обновите папку мода из того же архива)." `
                        -FixEn "Run Install_Engine.cmd inside the mod folder (and ensure both bin and mod match the same archive)."
                }
            } else {
                $imports = @(Get-PeImportedDlls -FilePath $exePath)
                if (@($imports | Where-Object { $_ -ieq "SDL3.dll" }).Count -gt 0) {
                    Add-CheckResult -Status "PASS" -Code "GAME_EXE_SDL3_IMPORT" `
                        -TitleRu ("Файл движка {0} поддерживает SDL3 геймпад" -f $expectedExeName) `
                        -TitleEn ("Engine binary {0} imports SDL3.dll" -f $expectedExeName)
                } else {
                    Add-CheckResult -Status "FAIL" -Code "GAME_EXE_NO_SDL3" `
                        -TitleRu ("Файл {0} не содержит поддержки геймпада (нет импорта SDL3.dll)" -f $expectedExeName) `
                        -TitleEn ("{0} lacks gamepad support (no SDL3.dll import)" -f $expectedExeName) `
                        -FixRu "Запустите Установить_движок.cmd внутри папки мода." `
                        -FixEn "Run Install_Engine.cmd inside the mod folder."
                }
            }
        }

        # 2. Check automatic backup (_gamepad_backup\ or legacy .orig)
        $backupOk = $false
        $backupDetailRu = ""
        $backupDetailEn = ""
        if (Test-Path -LiteralPath $backupManifestPath) {
            try {
                $bMan = ([System.IO.File]::ReadAllText($backupManifestPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                $exeEntry = @($bMan.files | Where-Object { $_.rel_path -ieq $expectedExeName } | Select-Object -First 1)
                if ($exeEntry.Count -gt 0) {
                    if ([bool]$exeEntry[0].existed_before) {
                        $bakExeFile = Join-Path $backupDir $expectedExeName
                        if (Test-Path -LiteralPath $bakExeFile) {
                            $backupOk = $true
                            $backupDetailRu = "Найдена папка _gamepad_backup с оригинальным $expectedExeName"
                            $backupDetailEn = "Found _gamepad_backup with original $expectedExeName"
                        }
                    } else {
                        $backupOk = $true
                        $backupDetailRu = "Учтено в _gamepad_backup: файл $expectedExeName добавлен модом (удаляется при откате)"
                        $backupDetailEn = "Tracked in _gamepad_backup: $expectedExeName was newly added (removed on restore)"
                    }
                }
            } catch {
                $backupOk = $false
            }
        } elseif (Test-Path -LiteralPath $origPath) {
            $backupOk = $true
            $backupDetailRu = "Найдена резервная копия $expectedExeName.orig"
            $backupDetailEn = "Found backup file $expectedExeName.orig"
        }

        if ($backupOk) {
            Add-CheckResult -Status "PASS" -Code "GAME_EXE_BACKUP_OK" `
                -TitleRu "Резервная копия для отката движка сохранена" `
                -TitleEn "Engine rollback backup is present" `
                -DetailRu $backupDetailRu -DetailEn $backupDetailEn
        } else {
            Add-CheckResult -Status "WARN" -Code "GAME_EXE_BACKUP_MISSING" `
                -TitleRu "Резервная копия оригинального движка не найдена в Anomaly\bin" `
                -TitleEn "Original engine backup not found in Anomaly\bin" `
                -DetailRu "Игра будет работать нормально, но для отката кнопкой Вернуть_оригинал.cmd нужна сохранённая копия." `
                -DetailEn "The game will run fine, but Restore_Original.cmd needs a saved backup." `
                -FixRu "Запустите Установить_движок.cmd перед заменой, чтобы автоматически создать _gamepad_backup." `
                -FixEn "Run Install_Engine.cmd to manage _gamepad_backup automatically."
        }

        # 3. Check SDL3.dll
        if (-not (Test-Path -LiteralPath $sdlPath)) {
            Add-CheckResult -Status "FAIL" -Code "GAME_SDL3_MISSING" `
                -TitleRu "В папке Anomaly\bin отсутствует библиотека SDL3.dll" `
                -TitleEn "SDL3.dll is missing from Anomaly\bin" `
                -DetailRu $sdlPath -DetailEn $sdlPath `
                -FixRu "Запустите Установить_движок.cmd внутри папки мода." `
                -FixEn "Run Install_Engine.cmd inside the mod folder."
        } elseif ($null -ne $manifest -and $manifest.sdl3.sha256) {
            $instSdlHash = (Get-FileHash -LiteralPath $sdlPath -Algorithm SHA256).Hash.ToUpperInvariant()
            $expSdlHash = $manifest.sdl3.sha256.ToUpperInvariant()
            if ($instSdlHash -eq $expSdlHash) {
                Add-CheckResult -Status "PASS" -Code "GAME_SDL3_HASH_OK" `
                    -TitleRu "Библиотека SDL3.dll установлена и совпадает с манифестом" `
                    -TitleEn "SDL3.dll is present and matches manifest SHA-256"
            } else {
                Add-CheckResult -Status "FAIL" -Code "GAME_SDL3_HASH_MISMATCH" `
                    -TitleRu "Версия SDL3.dll в Anomaly\bin отличается от версии из архива мода" `
                    -TitleEn "SDL3.dll in Anomaly\bin does not match the release manifest" `
                    -DetailRu ("Ожидался {0}, установлен {1}" -f $expSdlHash.Substring(0, 16), $instSdlHash.Substring(0, 16)) `
                    -DetailEn ("Expected {0}, installed {1}" -f $expSdlHash.Substring(0, 16), $instSdlHash.Substring(0, 16)) `
                    -FixRu "Запустите Установить_движок.cmd внутри папки мода." `
                    -FixEn "Run Install_Engine.cmd inside the mod folder."
            }
        } else {
            Add-CheckResult -Status "PASS" -Code "GAME_SDL3_PRESENT" `
                -TitleRu "Библиотека SDL3.dll найдена в Anomaly\bin" `
                -TitleEn "SDL3.dll found in Anomaly\bin"
        }

        # 3b. Check any extra anomaly_bin files from manifest (e.g. AnomalyDX11.exe or DLSS/FSR/Streamline DLLs)
        if ($null -ne $manifest) {
            $extraBins = @($manifest.files | Where-Object {
                $_.category -eq "anomaly_bin" -and
                ($_.PSObject.Properties.Name -contains "bin_rel_path") -and
                $_.bin_rel_path -and
                ($_.bin_rel_path -ine $expectedExeName) -and
                ($_.bin_rel_path -ine "SDL3.dll")
            })
            if ($extraBins.Count -gt 0) {
                $extraBad = @()
                foreach ($eb in $extraBins) {
                    $ebPath = Join-Path $binDir ($eb.bin_rel_path -replace "/", "\")
                    if (-not (Test-Path -LiteralPath $ebPath)) {
                        $extraBad += "MISSING: $($eb.bin_rel_path)"
                    } else {
                        $ebHash = (Get-FileHash -LiteralPath $ebPath -Algorithm SHA256).Hash.ToUpperInvariant()
                        if ($ebHash -ne $eb.sha256.ToUpperInvariant()) {
                            $extraBad += "MISMATCH: $($eb.bin_rel_path)"
                        }
                    }
                }
                if ($extraBad.Count -eq 0) {
                    Add-CheckResult -Status "PASS" -Code "GAME_EXTRA_BIN_OK" `
                        -TitleRu "Все дополнительные файлы движка и библиотеки в Anomaly\bin совпадают с манифестом" `
                        -TitleEn "All additional engine binaries and runtime DLLs in Anomaly\bin match manifest" `
                        -DetailRu ("Проверено файлов: {0}" -f $extraBins.Count) `
                        -DetailEn ("Verified files: {0}" -f $extraBins.Count)
                } else {
                    Add-CheckResult -Status "FAIL" -Code "GAME_EXTRA_BIN_FAIL" `
                        -TitleRu "Не хватает или изменены дополнительные файлы в Anomaly\bin" `
                        -TitleEn "Missing or mismatched additional engine files in Anomaly\bin" `
                        -DetailRu ($extraBad[0..([Math]::Min(4, $extraBad.Count - 1))] -join "; ") `
                        -DetailEn ($extraBad[0..([Math]::Min(4, $extraBad.Count - 1))] -join "; ") `
                        -FixRu "Запустите Установить_движок.cmd внутри папки мода." `
                        -FixEn "Run Install_Engine.cmd inside the mod folder."
                }
            }
        }

        # 4. Check installed mod files (MO2 mods\<ModName> or standalone Anomaly)
        $installedModRoot = if (-not [string]::IsNullOrWhiteSpace($Mo2Root)) {
            Join-Path $Mo2Root ("mods\{0}" -f $ModName)
        } else {
            $AnomalyRoot
        }

        if (-not (Test-Path -LiteralPath (Join-Path $installedModRoot "gamedata"))) {
            $whereHintRu = if ($Mo2Root) { "Импортируйте архив мода через Mod Organizer 2 (Install a new mod from an archive) в $Mo2Root\mods\$ModName." } else { "Укажите -Mo2Root для сборки с MO2 или скопируйте gamedata в папку Anomaly." }
            $whereHintEn = if ($Mo2Root) { "Install the mod archive directly in Mod Organizer 2 into $Mo2Root\mods\$ModName." } else { "Specify -Mo2Root for MO2 setups, or copy gamedata into Anomaly root." }
            Add-CheckResult -Status "FAIL" -Code "MOD_GAMEDATA_MISSING" `
                -TitleRu "Не найдены игровые файлы мода (папка gamedata)" `
                -TitleEn "Mod gamedata files not found" `
                -DetailRu (Join-Path $installedModRoot "gamedata") -DetailEn (Join-Path $installedModRoot "gamedata") `
                -FixRu $whereHintRu -FixEn $whereHintEn
        } elseif ($null -ne $manifest) {
            $modEntries = @($manifest.files | Where-Object { $_.category -in @("mod_gamedata", "gamma_screen_override", "dlss_overlay_gamedata") })
            $missingModFiles = @()
            $changedModFiles = @()
            foreach ($me in $modEntries) {
                $relGd = $me.gamedata_rel_path -replace "/", "\"
                $targetFile = Join-Path $installedModRoot $relGd
                if (-not (Test-Path -LiteralPath $targetFile)) {
                    $missingModFiles += $relGd
                } else {
                    $curHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash.ToUpperInvariant()
                    if ($curHash -ne $me.sha256.ToUpperInvariant()) {
                        $changedModFiles += $relGd
                    }
                }
            }
            if ($missingModFiles.Count -eq 0 -and $changedModFiles.Count -eq 0) {
                Add-CheckResult -Status "PASS" -Code "MOD_FILES_MANIFEST_OK" `
                    -TitleRu "Все файлы мода установлены без потерь и искажений" `
                    -TitleEn "All installed mod files match the SHA-256 manifest" `
                    -DetailRu ("Проверено файлов gamedata: {0}" -f $modEntries.Count) `
                    -DetailEn ("Verified gamedata files: {0}" -f $modEntries.Count)
            } else {
                $summaryErr = @()
                if ($missingModFiles.Count -gt 0) { $summaryErr += ("отсутствует / missing ({0}): {1}" -f $missingModFiles.Count, ($missingModFiles[0..([Math]::Min(2, $missingModFiles.Count - 1))] -join ", ")) }
                if ($changedModFiles.Count -gt 0) { $summaryErr += ("изменено / modified ({0}): {1}" -f $changedModFiles.Count, ($changedModFiles[0..([Math]::Min(2, $changedModFiles.Count - 1))] -join ", ")) }
                Add-CheckResult -Status "FAIL" -Code "MOD_FILES_MISMATCH" `
                    -TitleRu "Часть файлов мода отсутствует или повреждена/перезаписана" `
                    -TitleEn "Some installed mod files are missing or modified" `
                    -DetailRu ($summaryErr -join " | ") -DetailEn ($summaryErr -join " | ") `
                    -FixRu "Переустановите архив мода в MO2 с заменой файлов." `
                    -FixEn "Reinstall the mod archive in MO2 and choose Replace."
            }
        }

        # 5. Check MO2 modlist.txt load order & higher-priority collisions (when -Mo2Root is given)
        if (-not [string]::IsNullOrWhiteSpace($Mo2Root)) {
            if (-not (Test-Path -LiteralPath $Mo2Root)) {
                Add-CheckResult -Status "FAIL" -Code "MO2_ROOT_MISSING" `
                    -TitleRu "Папка Mod Organizer 2 не найдена" `
                    -TitleEn "Mod Organizer 2 folder not found" `
                    -DetailRu $Mo2Root -DetailEn $Mo2Root `
                    -FixRu "Проверьте путь в параметре -Mo2Root." -FixEn "Verify the -Mo2Root path."
            } else {
                $profDir = $null
                if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
                    $cand = Join-Path $Mo2Root ("profiles\{0}" -f $ProfileName)
                    if (Test-Path -LiteralPath $cand) { $profDir = $cand }
                }
                if ($null -eq $profDir) {
                    $mo2Ini = Join-Path $Mo2Root "ModOrganizer.ini"
                    if (Test-Path -LiteralPath $mo2Ini) {
                        $selLine = Get-Content -LiteralPath $mo2Ini -Encoding UTF8 | Where-Object { $_ -match "^selected_profile=" } | Select-Object -First 1
                        if ($selLine) {
                            $rawProf = ($selLine -replace "^selected_profile=", "").Trim()
                            $rawProf = $rawProf -replace "^@ByteArray\((.*)\)$", '$1'
                            $cand = Join-Path $Mo2Root ("profiles\{0}" -f $rawProf)
                            if (Test-Path -LiteralPath $cand) { $profDir = $cand }
                        }
                    }
                }
                if ($null -eq $profDir) {
                    foreach ($fallbackProf in @("G.A.M.M.A", "Default")) {
                        $cand = Join-Path $Mo2Root ("profiles\{0}" -f $fallbackProf)
                        if (Test-Path -LiteralPath $cand) { $profDir = $cand; break }
                    }
                }
                if ($null -eq $profDir) {
                    $firstMl = Get-ChildItem -Path (Join-Path $Mo2Root "profiles") -Filter "modlist.txt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($firstMl) { $profDir = $firstMl.DirectoryName }
                }

                $modlistPath = if ($profDir) { Join-Path $profDir "modlist.txt" } else { "" }
                if (-not $modlistPath -or -not (Test-Path -LiteralPath $modlistPath)) {
                    Add-CheckResult -Status "WARN" -Code "MO2_MODLIST_NOT_FOUND" `
                        -TitleRu "Не найден профиль modlist.txt в Mod Organizer 2" `
                        -TitleEn "Could not locate active profile modlist.txt in Mod Organizer 2" `
                        -FixRu "Убедитесь вручную, что мод включён и стоит в самом низу списка MO2." `
                        -FixEn "Verify manually in MO2 that the mod is checked and placed at the very bottom."
                } else {
                    # In MO2 modlist.txt: line 0 (top of file) = bottom of MO2 UI = HIGHEST priority
                    $mlLines = @(Get-Content -LiteralPath $modlistPath -Encoding UTF8 | Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#")
                    })
                    $ourIdx = -1
                    $ourState = ""
                    for ($i = 0; $i -lt $mlLines.Count; $i++) {
                        $ln = $mlLines[$i]
                        $prefix = $ln.Substring(0, 1)
                        $mName = $ln.Substring(1)
                        if ($mName -ieq $ModName) {
                            $ourIdx = $i
                            $ourState = $prefix
                            break
                        }
                    }

                    if ($ourIdx -lt 0) {
                        Add-CheckResult -Status "FAIL" -Code "MO2_MOD_NOT_REGISTERED" `
                            -TitleRu ("Мод «{0}» ещё не добавлен в профиль MO2" -f $ModName) `
                            -TitleEn ("Mod '{0}' is not listed in MO2 modlist.txt" -f $ModName) `
                            -FixRu "Откройте Mod Organizer 2, нажмите F5, перетащите мод в самый низ и поставьте галочку." `
                            -FixEn "Open Mod Organizer 2, press F5, drag the mod to the very bottom, and check its box."
                    } elseif ($ourState -ne "+") {
                        Add-CheckResult -Status "FAIL" -Code "MO2_MOD_DISABLED" `
                            -TitleRu ("Мод «{0}» выключен (снята галочка) в Mod Organizer 2" -f $ModName) `
                            -TitleEn ("Mod '{0}' is unchecked (disabled) in Mod Organizer 2" -f $ModName) `
                            -FixRu ("Поставьте галочку напротив «{0}» в левом списке MO2." -f $ModName) `
                            -FixEn ("Enable the checkbox next to '{0}' in MO2." -f $ModName)
                    } else {
                        # Scan mods with HIGHER priority than ours (index < ourIdx in modlist.txt)
                        $ourRelPaths = @{}
                        $ourGdRoot = Join-Path $Mo2Root ("mods\{0}\gamedata" -f $ModName)
                        if (Test-Path -LiteralPath $ourGdRoot) {
                            Get-ChildItem -LiteralPath $ourGdRoot -Recurse -File | ForEach-Object {
                                $rp = $_.FullName.Substring($ourGdRoot.Length + 1).ToLowerInvariant()
                                $ourRelPaths[$rp] = $true
                            }
                        }

                        $collidingMods = New-Object System.Collections.Generic.List[string]
                        for ($i = 0; $i -lt $ourIdx; $i++) {
                            $ln = $mlLines[$i]
                            if (-not $ln.StartsWith("+")) { continue }
                            $higherMod = $ln.Substring(1)
                            $higherGd = Join-Path $Mo2Root ("mods\{0}\gamedata" -f $higherMod)
                            if (-not (Test-Path -LiteralPath $higherGd)) { continue }
                            foreach ($rp in $ourRelPaths.Keys) {
                                if (Test-Path -LiteralPath (Join-Path $higherGd $rp)) {
                                    $collidingMods.Add("$higherMod ($rp)")
                                    break
                                }
                            }
                        }

                        if ($collidingMods.Count -gt 0) {
                            $colSample = ($collidingMods | Select-Object -First 3) -join "; "
                            Add-CheckResult -Status "FAIL" -Code "MO2_FILE_OVERWRITTEN" `
                                -TitleRu "Другой мод стоит ниже в MO2 и перезаписывает файлы геймпада" `
                                -TitleEn "Another mod has higher priority in MO2 and overwrites gamepad files" `
                                -DetailRu $colSample -DetailEn $colSample `
                                -FixRu ("Перетащите «{0}» В САМЫЙ НИЗ левого списка Mod Organizer 2." -f $ModName) `
                                -FixEn ("Drag '{0}' to the VERY BOTTOM of the left pane in Mod Organizer 2." -f $ModName)
                        } else {
                            Add-CheckResult -Status "PASS" -Code "MO2_LOAD_ORDER_OK" `
                                -TitleRu "Мод включён в MO2, ни один другой мод не перезаписывает его файлы" `
                                -TitleEn "Mod is enabled in MO2 with zero file overwrites from higher-priority mods" `
                                -DetailRu ("Позиция от низа списка MO2: {0}" -f $ourIdx) `
                                -DetailEn ("Distance from bottom of MO2 list: {0}" -f $ourIdx)
                        }
                    }
                }
            }
        }

        # 6. Check user settings appdata\gamepad\profile.ltx (Read-Only)
        $profileLtx = Join-Path $AnomalyRoot "appdata\gamepad\profile.ltx"
        if (Test-Path -LiteralPath $profileLtx) {
            $profText = [System.IO.File]::ReadAllText($profileLtx, [System.Text.Encoding]::UTF8)
            if ($profText -match "\[[^\]]+\]") {
                Add-CheckResult -Status "PASS" -Code "USER_PROFILE_OK" `
                    -TitleRu "Пользовательский профиль настроек геймпада (appdata\gamepad\profile.ltx) в порядке" `
                    -TitleEn "User gamepad profile (appdata\gamepad\profile.ltx) is present and valid"
            } else {
                Add-CheckResult -Status "WARN" -Code "USER_PROFILE_EMPTY" `
                    -TitleRu "Файл appdata\gamepad\profile.ltx пуст или не содержит секций" `
                    -TitleEn "appdata\gamepad\profile.ltx has no LTX sections" `
                    -FixRu "При запуске игры мод автоматически восстановит стандартные настройки." `
                    -FixEn "The mod will populate default bindings automatically on next launch."
            }
        } else {
            Add-CheckResult -Status "PASS" -Code "USER_PROFILE_FIRST_RUN" `
                -TitleRu "Профиль appdata\gamepad\profile.ltx будет создан автоматически при первом запуске" `
                -TitleEn "appdata\gamepad\profile.ltx will be created automatically on first launch"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AnomalyRoot) -and [string]::IsNullOrWhiteSpace($PackageRoot)) {
    Add-CheckResult -Status "FAIL" -Code "NO_TARGET_SPECIFIED" `
        -TitleRu "Не указана папка для проверки" `
        -TitleEn "No target path specified to verify" `
        -FixRu "Запустите скрипт из папки мода в MO2 или передайте -AnomalyRoot ""D:\Anomaly"" -Mo2Root ""D:\GAMMA"" (либо -PackageRoot)." `
        -FixEn "Run from inside your MO2 mod folder or pass -AnomalyRoot ""D:\Anomaly"" -Mo2Root ""D:\GAMMA"" (or -PackageRoot)."
}

$passCount = @($Results | Where-Object { $_.Status -eq "PASS" }).Count
$warnCount = @($Results | Where-Object { $_.Status -eq "WARN" }).Count
$failCount = @($Results | Where-Object { $_.Status -eq "FAIL" }).Count

$exitCode = if ($failCount -gt 0) { 1 } elseif ($warnCount -gt 0) { 2 } else { 0 }
$overall = switch ($exitCode) { 0 { "PASS" } 2 { "WARN" } default { "FAIL" } }
$sumColor = switch ($exitCode) { 0 { "Green" } 2 { "Yellow" } default { "Red" } }

Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("ИТОГ / SUMMARY: {0}  (PASS={1}, WARN={2}, FAIL={3})  [ExitCode={4}]" -f $overall, $passCount, $warnCount, $failCount, $exitCode) -ForegroundColor $sumColor
Write-Host "========================================================================" -ForegroundColor White

if (-not [string]::IsNullOrWhiteSpace($JsonOut)) {
    $outObj = [ordered]@{
        overall   = $overall
        exit_code = $exitCode
        counts    = [ordered]@{ pass = $passCount; warn = $warnCount; fail = $failCount }
        manifest  = $resolvedManifest
        results   = $Results
    }
    $outParent = Split-Path -Parent $JsonOut
    if (-not [string]::IsNullOrWhiteSpace($outParent) -and -not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($JsonOut, ($outObj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

exit $exitCode
