<#
.SYNOPSIS
    Gamepad At Your Service — Release Archive Builder (I1.1, D64).

.DESCRIPTION
    Assembles a distributable release archive following docs/kb/27-packaging-design.md
    and D64 (2026-11-14 base switch):
      - Primary target (-Target gamma-monolith): original G.A.M.M.A. engine
        (xray-monolith by themrdemonized, AnomalyDX11AVX.exe from ports\PORT-G\out)
        + original G.A.M.M.A. modpack.
      - Secondary target (-Target anomaly-vanilla): original S.T.A.L.K.E.R. Anomaly
        1.5.2/1.5.3 (AnomalyDX11AVX.exe from ports\PORT-A\out, without G.A.M.M.A.-only
        screen override files).
      - Optional package (-Target pbr-dx12-optional): Optional PBR + DX12 + DLSS
        build (AnomalyDX12.exe).

    Features:
      - Re-encodes UTF-8/UTF-16 .script/.ltx/.xml files into strict Windows-1251 without BOM
        (while preserving already-valid CP1251 files byte-for-byte without corruption).
      - Excludes debug/profiler/autotest/backup files, redistributed shaders (D23), and
        obsolete unreferenced draft .dds textures.
      - Generates THIRD-PARTY-NOTICES.txt + THIRD_PARTY\ license bundle, meta.ini,
        manifest.sha256.json, and SHA256SUMS.txt.
      - Supports -DryRun (prints full file plan without writing staging or .zip).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("gamma-monolith", "anomaly-vanilla", "pbr-dx12-optional", "gamma-monolith-dlss")]
    [string]$Target = "gamma-monolith",

    [Parameter(Mandatory = $false)]
    [string]$Version = "0.2.0",

    [Parameter(Mandatory = $false)]
    [string]$ModSourceDir = "D:\GAMMA-Gamepad-Lab\build\mod",

    [Parameter(Mandatory = $false)]
    [string]$EngineExe = "",

    # gamma-monolith-dlss: runtime-файлы DLSS/FSR/Streamline (bin) и DLSS-оверлей gamedata (меню + шейдеры)
    [Parameter(Mandatory = $false)]
    [string]$DlssStandBin = "D:\GAMMA-Gamepad-Lab\may-test-dlssin",

    [Parameter(Mandatory = $false)]
    [string]$DlssExtrasDir = "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may-dlss\extras\dlss_gamma",

    [Parameter(Mandatory = $false)]
    [string]$SdlDllPath = "D:\GAMMA-Gamepad-Lab\game\bin\SDL3.dll",

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "D:\GAMMA-Gamepad-Lab\release",

    [Parameter(Mandatory = $false)]
    [string]$ModFolderName = "GAMMA Gamepad & Tactical UI",

    [Parameter(Mandatory = $false)]
    [switch]$AllowEngineStub,

    [Parameter(Mandatory = $false)]
    [bool]$IncludeGammaScreenOverrides = $true,

    [Parameter(Mandatory = $false)]
    [switch]$StrictCleanRoom,

    [Parameter(Mandatory = $false)]
    [switch]$KeepStaging,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom     = New-Object System.Text.UTF8Encoding($true)
$Utf8Strict  = New-Object System.Text.UTF8Encoding($false, $true)
$Cp1251Strict = [System.Text.Encoding]::GetEncoding(
    1251,
    [System.Text.EncoderFallback]::ExceptionFallback,
    [System.Text.DecoderFallback]::ExceptionFallback
)
$Cp1252Strict = [System.Text.Encoding]::GetEncoding(
    1252,
    [System.Text.EncoderFallback]::ExceptionFallback,
    [System.Text.DecoderFallback]::ExceptionFallback
)

$RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PkgToolDir = $PSScriptRoot

if ($Target -eq "anomaly-vanilla" -or $StrictCleanRoom) {
    $IncludeGammaScreenOverrides = $false
}

# G.A.M.M.A.-specific foreign/vanilla UI files modified in WS1 / FW1 / DIALOGS
$GammaScreenOverrideFiles = @{
    "gamedata\scripts\ui_workshop.script"           = $true
    "gamedata\scripts\ui_furniture_workshop.script" = $true
    "gamedata\scripts\ui_mm_faction_select.script"  = $true
    "gamedata\scripts\ui_mod_elements.script"       = $true
    "gamedata\scripts\ui_ctrl_lighting.script"      = $true
    "gamedata\configs\ui\ui_workshop_16.xml"        = $true
}

# Verified unreferenced draft DDS iterations in build/mod/gamedata/textures/ui/
$ObsoleteDraftDdsPatterns = @(
    "^ui_gp_inventory_footer_(audit|equal|lettergrid|reference|woven)_v\d+\.dds$",
    "^ui_gp_inv_btn_[abxy]_carbon.*\.dds$",
    "^ui_gp_inv_(lt|rt)_carbon.*\.dds$",
    "^ui_gp_inv_(a|b|x|y|lt|rt)_block\.dds$",
    "^ui_gp_inv_equipment_wide_rail_v5\.dds$",
    "^ui_gp_menu_shortcuts\.dds$"
)

function Resolve-EngineExecutable {
    $expectedExeName = if ($Target -eq "pbr-dx12-optional") { "AnomalyDX12.exe" } elseif ($Target -eq "gamma-monolith-dlss") { "AnomalyDX12-DLSS.exe" } else { "AnomalyDX11AVX.exe" }

    if (-not [string]::IsNullOrWhiteSpace($EngineExe)) {
        if (-not (Test-Path -LiteralPath $EngineExe)) {
            throw "Explicit -EngineExe path does not exist: $EngineExe"
        }
        return [PSCustomObject]@{
            ExeName    = $expectedExeName
            SourcePath = (Resolve-Path -LiteralPath $EngineExe).Path
            IsStub     = $false
            StubReason = ""
        }
    }

    $candidates = switch ($Target) {
        "gamma-monolith" {
            @(
                "D:\GAMMA-Gamepad-Lab\ports\PORT-G\out\AnomalyDX11AVX.exe",
                "D:\GAMMA-Gamepad-Lab\ports\PORT-G\out\AnomalyDX11.exe"
            )
        }
        "anomaly-vanilla" {
            @(
                "D:\GAMMA-Gamepad-Lab\ports\PORT-A\out\AnomalyDX11AVX.exe",
                "D:\GAMMA-Gamepad-Lab\ports\PORT-A\out\AnomalyDX11.exe"
            )
        }
        "gamma-monolith-dlss" {
            @("D:\GAMMA-Gamepad-Lab\may-test-dlssin\AnomalyDX12-DLSS.exe")
        }
        "pbr-dx12-optional" {
            @(
                "D:\GAMMA-Gamepad-Lab\build\engine\_build\_game\bin_dbg\AnomalyDX12.exe",
                "D:\GAMMA-Gamepad-Lab\game\bin\AnomalyDX12-DIALOGS.exe",
                "D:\GAMMA-Gamepad-Lab\game\bin\AnomalyDX12.exe"
            )
        }
    }

    $existing = @($candidates | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object LastWriteTimeUtc -Descending)
    if ($existing.Count -gt 0) {
        return [PSCustomObject]@{
            ExeName    = $expectedExeName
            SourcePath = $existing[0].FullName
            IsStub     = $false
            StubReason = ""
        }
    }

    if ($AllowEngineStub) {
        $reason = if ($Target -eq "gamma-monolith") { "pending_port_g_build (ports/PORT-G/out)" } else { "pending_port_a_build (ports/PORT-A/out)" }
        return [PSCustomObject]@{
            ExeName    = $expectedExeName
            SourcePath = ""
            IsStub     = $true
            StubReason = $reason
        }
    }

    throw ("No built engine executable found for target '{0}' (checked: {1}). Pass -EngineExe <path> or -AllowEngineStub for pre-build test packaging." -f $Target, ($candidates -join ", "))
}

function Get-ModFileDisposition {
    param([System.IO.FileInfo]$File, [string]$RelPath)

    $relNorm = $RelPath -replace "/", "\"
    $name = $File.Name
    $ext = $File.Extension.ToLowerInvariant()

    if (-not $relNorm.StartsWith("gamedata\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "non_gamedata_root_file" }
    }
    if ($ext -in @(".bak", ".orig", ".tmp", ".log", ".pdb", ".lib", ".exp", ".dll", ".exe") -or $name.EndsWith("~") -or $name -ieq "thumbs.db") {
        return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "backup_or_binary_artifact" }
    }
    if ($relNorm -match "(?i)^gamedata\\shaders\\") {
        return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "foreign_pbr_sss_shader_d23_d64" }
    }
    if ($relNorm -match "(?i)^gamedata\\scripts\\(zz_gp_|qa_autotest_|gp_testkit)" -or
        $name -match "(?i)(_test_suite|_test_harness)\.script$" -or
        $relNorm -ieq "gamedata\configs\ui\ui_gp_testkit.xml") {
        return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "debug_profiler_or_autotest" }
    }
    if ($relNorm -match "(?i)^gamedata\\textures\\ui\\" -and $ext -eq ".dds") {
        foreach ($pat in $ObsoleteDraftDdsPatterns) {
            if ($name -match $pat) {
                return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "unreferenced_draft_dds" }
            }
        }
    }
    if ($GammaScreenOverrideFiles.ContainsKey($relNorm)) {
        if (-not $IncludeGammaScreenOverrides) {
            return [PSCustomObject]@{ Include = $false; Category = "excluded"; Reason = "gamma_screen_override_omitted" }
        }
        return [PSCustomObject]@{ Include = $true; Category = "gamma_screen_override"; Reason = "included_gamma_screen_override" }
    }
    return [PSCustomObject]@{ Include = $true; Category = "mod_gamedata"; Reason = "production_gamedata" }
}

function Convert-GameTextToTargetBytes {
    param([string]$SourcePath, [string]$RelPath)

    $raw = [System.IO.File]::ReadAllBytes($SourcePath)
    for ($i = 0; $i -lt $raw.Length; $i++) {
        if ($raw[$i] -eq 0 -and -not ($raw.Length -ge 2 -and (($raw[0] -eq 0xFF -and $raw[1] -eq 0xFE) -or ($raw[0] -eq 0xFE -and $raw[1] -eq 0xFF)))) {
            throw "NUL byte detected in text file: $RelPath"
        }
    }

    $isWestEuroLang = ($RelPath -match "(?i)^gamedata\\configs\\text\\(fra|ger|ita|spa|pol)\\")
    $targetEnc = if ($isWestEuroLang) { $Cp1252Strict } else { $Cp1251Strict }
    $targetEncName = if ($isWestEuroLang) { "windows-1252" } else { "windows-1251" }

    # 1. UTF-16 LE / BE BOM
    if ($raw.Length -ge 2 -and $raw[0] -eq 0xFF -and $raw[1] -eq 0xFE) {
        $str = [System.Text.Encoding]::Unicode.GetString($raw, 2, $raw.Length - 2)
        return [PSCustomObject]@{ Bytes = $targetEnc.GetBytes($str); Action = "reencoded_utf16le_to_$targetEncName" }
    }
    if ($raw.Length -ge 2 -and $raw[0] -eq 0xFE -and $raw[1] -eq 0xFF) {
        $str = [System.Text.Encoding]::BigEndianUnicode.GetString($raw, 2, $raw.Length - 2)
        return [PSCustomObject]@{ Bytes = $targetEnc.GetBytes($str); Action = "reencoded_utf16be_to_$targetEncName" }
    }

    # 2. UTF-8 BOM
    $offset = 0
    $hadUtf8Bom = $false
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
        $offset = 3
        $hadUtf8Bom = $true
    }

    # Check if pure 7-bit ASCII
    $hasHighByte = $false
    for ($i = $offset; $i -lt $raw.Length; $i++) {
        if ($raw[$i] -ge 0x80) { $hasHighByte = $true; break }
    }
    if (-not $hasHighByte) {
        if ($hadUtf8Bom) {
            $slice = New-Object byte[] ($raw.Length - 3)
            [Array]::Copy($raw, 3, $slice, 0, $slice.Length)
            return [PSCustomObject]@{ Bytes = $slice; Action = "stripped_utf8_bom_ascii" }
        }
        return [PSCustomObject]@{ Bytes = $raw; Action = "kept_ascii_clean" }
    }

    # Try strict UTF-8 decode: multi-byte UTF-8 text succeeds here, whereas single-byte CP1251 Cyrillic throws!
    $utf8Decoded = $null
    try {
        $utf8Decoded = $Utf8Strict.GetString($raw, $offset, $raw.Length - $offset)
    } catch {
        $utf8Decoded = $null
    }

    if ($null -ne $utf8Decoded) {
        $encoded = $targetEnc.GetBytes($utf8Decoded)
        $roundTrip = $targetEnc.GetString($encoded)
        if ($roundTrip -ne $utf8Decoded) {
            throw "Character loss during UTF-8 -> $targetEncName conversion in $RelPath"
        }
        return [PSCustomObject]@{ Bytes = $encoded; Action = "reencoded_utf8_to_$targetEncName" }
    }

    # Otherwise must already be valid single-byte target encoding without BOM
    $verifiedStr = $targetEnc.GetString($raw)
    if ($verifiedStr.IndexOf([char]0xFFFD) -ge 0) {
        throw "Invalid byte sequence in $RelPath for $targetEncName"
    }
    return [PSCustomObject]@{ Bytes = $raw; Action = "verified_$targetEncName" }
}

function New-ThirdPartyNoticesText {
    param([string]$BuildTarget, [string]$RelVersion)
    $pbrBlock = if ($BuildTarget -in @("pbr-dx12-optional", "gamma-monolith-dlss")) {
@"

--------------------------------------------------------------------------------
OPTIONAL PBR / DX12 / DLSS BUILD COMPONENTS (present ONLY in pbr-dx12-optional)
--------------------------------------------------------------------------------
- NVIDIA DLSS SDK (NGX) & NVIDIA Streamline SDK — Copyright (c) NVIDIA
  Corporation. Governed by NVIDIA DLSS / Streamline license terms (see
  THIRD_PARTY\DLSS-LICENSE.txt and Streamline-LICENSE.txt). Runtime DLLs are
  NOT bundled inside the MO2 mod archive.
- AMD FidelityFX SDK / FSR 3 — Copyright (c) Advanced Micro Devices, Inc.
  Licensed under the MIT License (see THIRD_PARTY\FSR3-LICENSE.txt).
- Microsoft DirectX 12 Agility SDK — Copyright (c) Microsoft Corporation
  (see THIRD_PARTY\AgilitySDK-LICENSE.txt).
"@
    } else {
        ""
    }

    return @"
================================================================================
GAMEPAD AT YOUR SERVICE (v$RelVersion, target: $BuildTarget)
THIRD-PARTY SOFTWARE NOTICES & ATTRIBUTIONS
================================================================================

1. X-Ray Engine (1.6) & X-Ray Monolith / OpenXRay
   - Original X-Ray Engine 1.6 Copyright (c) GSC Game World. Non-commercial distribution
     only pursuant to GSC Game World's open-source grant (see THIRD_PARTY\License-XRay-GSC.txt).
   - S.T.A.L.K.E.R. Anomaly Monolith Engine & Modded Exes contributions by Anomaly Team,
     OpenXRay contributors, and themrdemonized (https://github.com/themrdemonized/xray-monolith).

2. Simple DirectMedia Layer 3 (SDL3.dll — SDL 3.4.x)
   - Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
   - Licensed under the zlib License (see THIRD_PARTY\SDL3-LICENSE.txt).

3. OpenAL Soft (dynamically linked via Anomaly\bin\soft_oal.dll)
   - Licensed under the GNU Lesser General Public License v2.1 (LGPL-2.1-or-later).
   - Dynamically linked; users may replace soft_oal.dll in Anomaly\bin\ with any
     ABI-compatible x64 OpenAL Soft build (https://github.com/kcat/openal-soft).

4. Libraries Statically Linked in X-Ray Engine Executable
   - LuaJIT 2.x (Copyright (C) 2005-2023 Mike Pall) & Lua 5.1 (PUC-Rio) — MIT License.
   - Luabind (Copyright (c) 2003-2010 Daniel Wallin, Arvid Norberg) — MIT License.
   - Dear ImGui (Copyright (c) 2014-2025 Omar Cornut) — MIT License.
   - Intel oneAPI Threading Building Blocks (oneTBB) — Apache License 2.0.
   - OpenSSL / SSLeay (xrCore\crypto) — OpenSSL & Original SSLeay Licenses:
     "This product includes cryptographic software written by Eric Young (eay@cryptsoft.com)"
     "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
   - Independent JPEG Group libjpeg 6b:
     "This software is based in part on the work of the Independent JPEG Group."
   - Xiph.Org libogg, libvorbis, libtheora — BSD 3-Clause License.
   - Open Dynamics Engine (ODE, Copyright (c) Russell L. Smith) — BSD 3-Clause License.
   - OPCODE 1.2 (Pierre Terdiman) — Author attribution notice.
   - CxImage (Davide Pizzolato), giflib, NVIDIA Texture Tools (NVTT) — zlib / MIT.
   - StackWalker (Jochen Kalmbach) — BSD 2-Clause License.
   - Unicode ICU Components — Unicode / ICU License.

5. Gamepad UI Icons, Glyphs & Clean-Room Compatibility Adapters
   - Vector Gamepad Diagrams (TheHoodieGuy02) — Creative Commons Zero v1.0 Universal
     (CC0-1.0, see THIRD_PARTY\VectorGamepad-CC0-LICENSE.txt).
   - Steam-Style Gamepad Icon Reference Pack — see THIRD_PARTY\SteamStylePack-LICENSE.txt.
   - Clean-room first-party gamepad glyphs & tactical UI atlases created for this project;
     public Lua API compatibility hooks interoperate with locally installed G.A.M.M.A.
     addons (GAMMA Mags Reloaded, AmmoCheck Enhanced, Quick Action Wheel by HarukaSai,
     Hideout Furniture by Aoldri, PAW by RavenAscendant, Ledge Grabbing by themrdemonized)
     without bundling their proprietary archives.
$pbrBlock
================================================================================
"@
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host (" BUILD RELEASE — Gamepad At Your Service v{0} [{1}]{2}" -f $Version, $Target, $(if ($DryRun) { " (DRY RUN)" } else { "" })) -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ModSourceDir)) {
    throw "ModSourceDir not found: $ModSourceDir"
}
if (-not (Test-Path -LiteralPath $SdlDllPath)) {
    throw "SdlDllPath not found: $SdlDllPath"
}

$engineInfo = Resolve-EngineExecutable
Write-Host ("Engine Target : {0} -> {1}" -f $engineInfo.ExeName, $(if ($engineInfo.IsStub) { "STUB ($($engineInfo.StubReason))" } else { $engineInfo.SourcePath }))
Write-Host ("SDL3 Runtime  : {0}" -f $SdlDllPath)
Write-Host ("Mod Source    : {0}" -f $ModSourceDir)

$modSourceResolved = (Resolve-Path -LiteralPath $ModSourceDir).Path
$allModFiles = @(Get-ChildItem -LiteralPath $modSourceResolved -Recurse -File | Sort-Object FullName)

$includedPlan = New-Object System.Collections.Generic.List[object]
$excludedPlan = New-Object System.Collections.Generic.List[object]

foreach ($f in $allModFiles) {
    $rel = $f.FullName.Substring($modSourceResolved.Length + 1)
    $disp = Get-ModFileDisposition -File $f -RelPath $rel
    if ($disp.Include) {
        $ext = $f.Extension.ToLowerInvariant()
        $encPlan = if ($ext -in @(".script", ".ltx", ".xml")) {
            (Convert-GameTextToTargetBytes -SourcePath $f.FullName -RelPath $rel)
        } else {
            $null
        }
        $outLen = if ($null -ne $encPlan) { $encPlan.Bytes.Length } else { $f.Length }
        $action = if ($null -ne $encPlan) { $encPlan.Action } else { "copy_binary" }
        $includedPlan.Add([PSCustomObject]@{
            SourcePath = $f.FullName
            RelPath    = $rel
            Category   = $disp.Category
            Action     = $action
            SizeBytes  = $outLen
            PreparedBytes = if ($null -ne $encPlan) { $encPlan.Bytes } else { $null }
        })
    } else {
        $excludedPlan.Add([PSCustomObject]@{
            RelPath   = $rel
            Reason    = $disp.Reason
            SizeBytes = $f.Length
        })
    }
}

if ($Target -eq "gamma-monolith-dlss") {
    if (-not (Test-Path -LiteralPath $DlssExtrasDir)) { throw "DlssExtrasDir not found: $DlssExtrasDir" }
    $extrasResolved = (Resolve-Path -LiteralPath $DlssExtrasDir).Path
    foreach ($f in @(Get-ChildItem -LiteralPath $extrasResolved -Recurse -File | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($extrasResolved.Length + 1)
        if (-not $rel.StartsWith("gamedata\", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $ext = $f.Extension.ToLowerInvariant()
        $encPlan = if ($ext -in @(".script", ".ltx", ".xml")) { (Convert-GameTextToTargetBytes -SourcePath $f.FullName -RelPath $rel) } else { $null }
        $includedPlan.Add([PSCustomObject]@{
            SourcePath = $f.FullName
            RelPath    = $rel
            Category   = "dlss_overlay_gamedata"
            Action     = $(if ($null -ne $encPlan) { $encPlan.Action } else { "copy_binary" })
            SizeBytes  = $(if ($null -ne $encPlan) { $encPlan.Bytes.Length } else { $f.Length })
            PreparedBytes = $(if ($null -ne $encPlan) { $encPlan.Bytes } else { $null })
        })
    }
}

$incBytes = ($includedPlan | Measure-Object -Property SizeBytes -Sum).Sum
$excBytes = ($excludedPlan | Measure-Object -Property SizeBytes -Sum).Sum
$reencodedCount = @($includedPlan | Where-Object { $_.Action -like "reencoded_*" -or $_.Action -like "stripped_*" }).Count

Write-Host ("Mod Files     : {0} included ({1:N2} MB), {2} excluded ({3:N2} MB), {4} re-encoded/BOM-stripped" -f `
    $includedPlan.Count, ($incBytes / 1MB), $excludedPlan.Count, ($excBytes / 1MB), $reencodedCount)

$excGroups = $excludedPlan | Group-Object Reason | Sort-Object Name
foreach ($g in $excGroups) {
    $gSum = ($g.Group | Measure-Object -Property SizeBytes -Sum).Sum
    Write-Host ("  - Excluded [{0}]: {1} files ({2:N2} MB)" -f $g.Name, $g.Count, ($gSum / 1MB)) -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host "`n--- DRY RUN: INCLUDED FILES ---" -ForegroundColor Green
    Write-Host ("  1_Copy_To_Anomaly_bin\{0} ({1})" -f $engineInfo.ExeName, $(if ($engineInfo.IsStub) { "STUB" } else { "$((Get-Item $engineInfo.SourcePath).Length) bytes" }))
    Write-Host ("  1_Copy_To_Anomaly_bin\SDL3.dll ({0} bytes)" -f (Get-Item -LiteralPath $SdlDllPath).Length)
    Write-Host "  1_Copy_To_Anomaly_bin\THIRD-PARTY-NOTICES.txt"
    foreach ($item in $includedPlan) {
        Write-Host ("  2_Install_In_MO2_mods\{0}\{1}  [{2} | {3} | {4} B]" -f $ModFolderName, $item.RelPath, $item.Category, $item.Action, $item.SizeBytes)
    }
    Write-Host "  3_Verify_Installation_ReadOnly\verify.ps1"
    Write-Host "  3_Verify_Installation_ReadOnly\manifest.sha256.json"
    Write-Host "  3_Verify_Installation_ReadOnly\SHA256SUMS.txt"
    Write-Host "  THIRD_PARTY\*"
    Write-Host "  README-RU.txt, README-EN.txt, THIRD-PARTY-NOTICES.txt, manifest.sha256.json, SHA256SUMS.txt"
    Write-Host "`nDRY RUN COMPLETE — zero files written." -ForegroundColor Green
    exit 0
}

# ==============================================================================
# Stage Release Directory
# ==============================================================================
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$OutputDirResolved = (Resolve-Path -LiteralPath $OutputDir).Path
$ArchiveStem = ("Gamepad-At-Your-Service-v{0}-{1}" -f $Version, $Target)
$StageContainer = Join-Path $OutputDirResolved ("_staging_{0}" -f $Target)
$StageRoot = Join-Path $StageContainer "Gamepad-At-Your-Service"
$ZipPath = Join-Path $OutputDirResolved ("{0}.zip" -f $ArchiveStem)

if (Test-Path -LiteralPath $StageContainer) {
    Remove-Item -LiteralPath $StageContainer -Recurse -Force
}

$Dir1Bin   = Join-Path $StageRoot "1_Copy_To_Anomaly_bin"
$Dir2Mod   = Join-Path $StageRoot ("2_Install_In_MO2_mods\{0}" -f $ModFolderName)
$Dir3Ver   = Join-Path $StageRoot "3_Verify_Installation_ReadOnly"
$DirLic    = Join-Path $StageRoot "THIRD_PARTY"

foreach ($d in @($Dir1Bin, $Dir2Mod, $Dir3Ver, $DirLic)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# 1. Populate 1_Copy_To_Anomaly_bin
$stagedExePath = Join-Path $Dir1Bin $engineInfo.ExeName
if ($engineInfo.IsStub) {
    $stubText = "PENDING_BUILD_STUB: target=$Target version=$Version reason=$($engineInfo.StubReason)`r`nReplace with compiled $($engineInfo.ExeName) from PORT-G/PORT-A before player distribution.`r`n"
    [System.IO.File]::WriteAllText($stagedExePath, $stubText, $Utf8NoBom)
} else {
    Copy-Item -LiteralPath $engineInfo.SourcePath -Destination $stagedExePath -Force
}
$stagedSdlPath = Join-Path $Dir1Bin "SDL3.dll"
Copy-Item -LiteralPath $SdlDllPath -Destination $stagedSdlPath -Force

if ($Target -eq "gamma-monolith-dlss") {
    # runtime DLSS/FSR/Streamline/Agility (без pdb, логов и самих exe/SDL3 — они ставятся отдельно)
    $dlssBinRoot = (Resolve-Path -LiteralPath $DlssStandBin).Path
    $dlssBinFiles = @(
        "nvngx_dlss.dll", "amd_fidelityfx_framegeneration_dx12.dll", "amd_fidelityfx_loader_dx12.dll", "amd_fidelityfx_upscaler_dx12.dll",
        "AMD-FIDELITYFX-LICENSE.md", "NVIDIA-DLSS-LICENSE.txt",
        "D3D12\D3D12Core.dll", "D3D12\AGILITY-SDK-LICENSE.txt",
        "streamline
vngx_dlssg.dll", "streamline\sl.common.dll", "streamline\sl.dlss_g.dll", "streamline\sl.interposer.dll",
        "streamline\sl.pcl.dll", "streamline\sl.reflex.dll", "streamline\RUNTIME.txt", "streamline\STREAMLINE-LICENSE.txt"
    )
    foreach ($rel in $dlssBinFiles) {
        $src = Join-Path $dlssBinRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { throw "DLSS runtime file missing: $src" }
        $dst = Join-Path $Dir1Bin $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$noticesText = (New-ThirdPartyNoticesText -BuildTarget $Target -RelVersion $Version) -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $Dir1Bin "THIRD-PARTY-NOTICES.txt"), $noticesText, $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $StageRoot "THIRD-PARTY-NOTICES.txt"), $noticesText, $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $DirLic "THIRD-PARTY-NOTICES.txt"), $noticesText, $Utf8NoBom)

# 2. Populate THIRD_PARTY license files
$licenseSources = @(
    @{ Src = "D:\GAMMA-Gamepad-Lab\ports\PORT-G\src\License.txt"; Fallback = "D:\GAMMA-Gamepad-Lab\build\engine\License.txt"; Dst = "License-XRay-GSC.txt" },
    @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\src\3rd party\SDL3\LICENSE.txt"; Fallback = ""; Dst = "SDL3-LICENSE.txt" },
    @{ Src = (Join-Path $RepoRoot "assets\third_party\vector-gamepad\LICENSE.txt"); Fallback = ""; Dst = "VectorGamepad-CC0-LICENSE.txt" },
    @{ Src = (Join-Path $RepoRoot "assets\gamepad_icons\steam_style_pack\LICENSE"); Fallback = ""; Dst = "SteamStylePack-LICENSE.txt" }
)
if ($Target -in @("pbr-dx12-optional", "gamma-monolith-dlss")) {
    $licenseSources += @(
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\DLSS\LICENSE.txt"; Fallback = ""; Dst = "DLSS-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\Streamline\LICENSE.txt"; Fallback = ""; Dst = "Streamline-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\FSR3\LICENSE.txt"; Fallback = ""; Dst = "FSR3-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\AgilitySDK\LICENSE.txt"; Fallback = ""; Dst = "AgilitySDK-LICENSE.txt" }
    )
}
foreach ($ls in $licenseSources) {
    $srcUse = if (Test-Path -LiteralPath $ls.Src) { $ls.Src } elseif ($ls.Fallback -and (Test-Path -LiteralPath $ls.Fallback)) { $ls.Fallback } else { "" }
    if ($srcUse) {
        Copy-Item -LiteralPath $srcUse -Destination (Join-Path $DirLic $ls.Dst) -Force
    }
}

# 3. Populate 2_Install_In_MO2_mods\<ModFolderName>
$metaIni = @"
[General]
modid=0
version=$Version
newestVersion=$Version
category="User Interface,"
installationFile=$ArchiveStem.zip
comments="Gamepad At Your Service ($Target) - place at the VERY BOTTOM of MO2"
notes="Step 1: copy 1_Copy_To_Anomaly_bin into Anomaly\bin"
"@ -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $Dir2Mod "meta.ini"), $metaIni, $Utf8NoBom)

foreach ($item in $includedPlan) {
    $dstPath = Join-Path $Dir2Mod $item.RelPath
    $dstParent = Split-Path -Parent $dstPath
    if (-not (Test-Path -LiteralPath $dstParent)) {
        New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
    }
    if ($null -ne $item.PreparedBytes) {
        [System.IO.File]::WriteAllBytes($dstPath, $item.PreparedBytes)
    } else {
        Copy-Item -LiteralPath $item.SourcePath -Destination $dstPath -Force
    }
}

# 4. Populate READMEs & 3_Verify_Installation_ReadOnly\verify.ps1
Copy-Item -LiteralPath (Join-Path $PkgToolDir "README-RU.txt") -Destination (Join-Path $StageRoot "README-RU.txt") -Force
Copy-Item -LiteralPath (Join-Path $PkgToolDir "README-EN.txt") -Destination (Join-Path $StageRoot "README-EN.txt") -Force
$verifySrcText = [System.IO.File]::ReadAllText((Join-Path $PkgToolDir "verify.ps1"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $Dir3Ver "verify.ps1"), $verifySrcText, $Utf8Bom)

# 5. Compute SHA-256 Manifest across all staged payload files
$modPrefix = ("2_Install_In_MO2_mods/{0}/" -f $ModFolderName)
$gammaOverrideNormSet = @{}
foreach ($k in $GammaScreenOverrideFiles.Keys) {
    $gammaOverrideNormSet[($k -replace "\\", "/").ToLowerInvariant()] = $true
}

$stagedFiles = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -File | Where-Object {
    $_.Name -notin @("manifest.sha256.json", "SHA256SUMS.txt")
} | Sort-Object FullName)

$manifestEntries = New-Object System.Collections.Generic.List[object]
$shaSumsLines = New-Object System.Collections.Generic.List[string]

foreach ($sf in $stagedFiles) {
    $relSlash = $sf.FullName.Substring($StageRoot.Length + 1) -replace "\\", "/"
    $hash = (Get-FileHash -LiteralPath $sf.FullName -Algorithm SHA256).Hash.ToUpperInvariant()

    $cat = "docs_and_tools"
    $gdRel = ""
    if ($relSlash.StartsWith("1_Copy_To_Anomaly_bin/")) {
        $cat = "anomaly_bin"
    } elseif ($relSlash.StartsWith("THIRD_PARTY/") -or $relSlash -eq "THIRD-PARTY-NOTICES.txt") {
        $cat = "license"
    } elseif ($relSlash.StartsWith($modPrefix)) {
        $sub = $relSlash.Substring($modPrefix.Length)
        if ($sub -eq "meta.ini") {
            $cat = "mo2_meta"
        } else {
            $gdRel = $sub
            if ($gammaOverrideNormSet.ContainsKey($sub.ToLowerInvariant())) {
                $cat = "gamma_screen_override"
            } else {
                $cat = "mod_gamedata"
            }
        }
    }

    $manifestEntries.Add([ordered]@{
        path              = $relSlash
        gamedata_rel_path = $gdRel
        category          = $cat
        size_bytes        = $sf.Length
        sha256            = $hash
    })
    $shaSumsLines.Add(("{0}  {1}" -f $hash.ToLowerInvariant(), $relSlash))
}

$exeHash = (Get-FileHash -LiteralPath $stagedExePath -Algorithm SHA256).Hash.ToUpperInvariant()
$sdlHash = (Get-FileHash -LiteralPath $stagedSdlPath -Algorithm SHA256).Hash.ToUpperInvariant()

$manifestObj = [ordered]@{
    schema_version  = 1
    package_name    = "Gamepad-At-Your-Service"
    version         = $Version
    target          = $Target
    is_optional_pbr = ($Target -eq "pbr-dx12-optional")
    built_at        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    mod_folder_name = $ModFolderName
    file_marker     = "GAYS_REL1_20261114"
    engine          = [ordered]@{
        exe_name     = $engineInfo.ExeName
        package_path = ("1_Copy_To_Anomaly_bin/{0}" -f $engineInfo.ExeName)
        size_bytes   = (Get-Item -LiteralPath $stagedExePath).Length
        sha256       = $exeHash
        is_stub      = $engineInfo.IsStub
        stub_reason  = $engineInfo.StubReason
    }
    sdl3            = [ordered]@{
        dll_name     = "SDL3.dll"
        package_path = "1_Copy_To_Anomaly_bin/SDL3.dll"
        size_bytes   = (Get-Item -LiteralPath $stagedSdlPath).Length
        sha256       = $sdlHash
    }
    counts          = [ordered]@{
        total_files   = $manifestEntries.Count
        gamedata_only = @($manifestEntries | Where-Object { $_.category -in @("mod_gamedata", "gamma_screen_override") }).Count
        excluded      = $excludedPlan.Count
        reencoded     = $reencodedCount
    }
    files           = $manifestEntries
}

$manifestJson = $manifestObj | ConvertTo-Json -Depth 6
$shaSumsText = ($shaSumsLines -join "`r`n") + "`r`n"

foreach ($destDir in @($StageRoot, $Dir3Ver)) {
    [System.IO.File]::WriteAllText((Join-Path $destDir "manifest.sha256.json"), $manifestJson, $Utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $destDir "SHA256SUMS.txt"), $shaSumsText, $Utf8NoBom)
}

# 6. Post-stage self-verification via verify.ps1 -PackageRoot
Write-Host "`nRunning read-only package verification gate..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir3Ver "verify.ps1") -PackageRoot $StageRoot -Lang ru
$verExit = $LASTEXITCODE
if ($verExit -eq 1) {
    throw "Post-stage verify.ps1 FAILED (exit code 1)!"
}

# 7. Compress .zip Archive
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $StageContainer,
    $ZipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$zipItem = Get-Item -LiteralPath $ZipPath
$zipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
$zipShaFile = "$ZipPath.sha256"
[System.IO.File]::WriteAllText($zipShaFile, ("{0}  {1}`r`n" -f $zipHash.ToLowerInvariant(), $zipItem.Name), $Utf8NoBom)

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $StageContainer -Recurse -Force
}

Write-Host "`n========================================================================" -ForegroundColor Green
Write-Host (" RELEASE ARCHIVE READY: {0}" -f $ZipPath) -ForegroundColor Green
Write-Host (" Size    : {0:N2} MB ({1} bytes)" -f ($zipItem.Length / 1MB), $zipItem.Length) -ForegroundColor Green
Write-Host (" SHA-256 : {0}" -f $zipHash) -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
