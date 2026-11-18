<#
.SYNOPSIS
    Gamepad At Your Service — MO2-Ready Release Archive Builder (D64 / MT-TEST).

.DESCRIPTION
    Assembles a distributable release archive ready for direct import into
    Mod Organizer 2 (Install a new mod from an archive):
      - Single top-level mod folder: GAMMA Gamepad & Tactical UI\
          meta.ini
          gamedata\                (strict Windows-1251 / 1252 without BOM)
          engine_files\            (files for <Anomaly>\bin\ + engine_helper.ps1)
          tools\verify.ps1         (read-only installation verifier)
          Установить_движок.cmd / Вернуть_оригинал.cmd
          Install_Engine.cmd    / Restore_Original.cmd
          README-RU.txt / README-EN.txt / THIRD-PARTY-NOTICES.txt / THIRD_PARTY\
          manifest.sha256.json / SHA256SUMS.txt

    Supported targets:
      - gamma-monolith (default): G.A.M.M.A. DX11/AVX + DX11 fallback from may-test\bin.
      - gamma-monolith-dlss: G.A.M.M.A. DX12 bridge (DLSS, FSR 3, Frame Generation) from
        may-test-dlss\bin + open-source DLSS shaders/menu from extras\dlss_gamma.
      - anomaly-vanilla: clean S.T.A.L.K.E.R. Anomaly 1.5.2/1.5.3 (PORT-A).
      - pbr-dx12-optional: optional PBR + DX12 + DLSS build (AnomalyDX12.exe).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("gamma-monolith", "anomaly-vanilla", "pbr-dx12-optional", "gamma-monolith-dlss")]
    [string]$Target = "gamma-monolith",

    [Parameter(Mandatory = $false)]
    [string]$Version = "0.2.2",

    [Parameter(Mandatory = $false)]
    [string]$ModSourceDir = "D:\GAMMA-Gamepad-Lab\build\mod",

    [Parameter(Mandatory = $false)]
    [string]$EngineExe = "",

    [Parameter(Mandatory = $false)]
    [string]$StandBinDir = "D:\GAMMA-Gamepad-Lab\may-test\bin",

    # gamma-monolith-dlss: runtime files (bin) and DLSS overlay gamedata (menu + shaders)
    [Parameter(Mandatory = $false)]
    [string]$DlssStandBin = "D:\GAMMA-Gamepad-Lab\may-test-dlss\bin",

    [Parameter(Mandatory = $false)]
    [string]$DlssExtrasDir = "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may-dlss\extras\dlss_gamma",

    [Parameter(Mandatory = $false)]
    [string]$SdlDllPath = "",

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

# G.A.M.M.A.-specific foreign/vanilla UI files (excluded on anomaly-vanilla / StrictCleanRoom)
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

# Closed PBR/SSS shaders that must never be redistributed in any release archive
$ForbiddenPbrShaderNames = @{
    "hashed_alpha.h"        = $true
    "ssfx_sss.ps"           = $true
    "ssfx_sss_ext.ps"       = $true
    "upscaler_reactive.ps"  = $true
    "screenspace_shadows.h" = $true
}

function Resolve-EnginePackageFiles {
    $expectedPrimaryName = switch ($Target) {
        "pbr-dx12-optional"   { "AnomalyDX12.exe" }
        "gamma-monolith-dlss" { "AnomalyDX12-DLSS.exe" }
        default               { "AnomalyDX11AVX.exe" }
    }

    $primarySource = ""
    $isStub = $false
    $stubReason = ""
    $additionalExes = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrWhiteSpace($EngineExe)) {
        if (-not (Test-Path -LiteralPath $EngineExe)) {
            throw "Explicit -EngineExe path does not exist: $EngineExe"
        }
        $primarySource = (Resolve-Path -LiteralPath $EngineExe).Path
        $expectedPrimaryName = [System.IO.Path]::GetFileName($primarySource)
    } else {
        $candidates = switch ($Target) {
            "gamma-monolith" {
                @(
                    (Join-Path $StandBinDir "AnomalyDX11AVX.exe"),
                    "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may\_out\bin\AnomalyDX11AVX.exe",
                    "D:\GAMMA-Gamepad-Lab\ports\PORT-G\out\AnomalyDX11AVX.exe",
                    (Join-Path $StandBinDir "AnomalyDX11.exe")
                )
            }
            "anomaly-vanilla" {
                @(
                    "D:\GAMMA-Gamepad-Lab\ports\PORT-A\out\AnomalyDX11AVX.exe",
                    "D:\GAMMA-Gamepad-Lab\ports\PORT-A\out\AnomalyDX11.exe"
                )
            }
            "gamma-monolith-dlss" {
                @(
                    (Join-Path $DlssStandBin "AnomalyDX12-DLSS.exe"),
                    "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may-dlss\_out\bin\AnomalyDX12-DLSS.exe"
                )
            }
            "pbr-dx12-optional" {
                @(
                    "D:\GAMMA-Gamepad-Lab\build\engine\_build\_game\bin_dbg\AnomalyDX12.exe",
                    "D:\GAMMA-Gamepad-Lab\game\bin\AnomalyDX12-DIALOGS.exe",
                    "D:\GAMMA-Gamepad-Lab\game\bin\AnomalyDX12.exe"
                )
            }
        }

        foreach ($cand in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path -LiteralPath $cand)) {
                $primarySource = (Resolve-Path -LiteralPath $cand).Path
                if ($Target -eq "anomaly-vanilla") {
                    $expectedPrimaryName = [System.IO.Path]::GetFileName($primarySource)
                }
                break
            }
        }

        if (-not $primarySource) {
            if ($AllowEngineStub) {
                $isStub = $true
                $stubReason = "pending_engine_build ($Target)"
            } else {
                throw ("No built engine executable found for target '{0}' (checked: {1}). Pass -EngineExe <path> or -AllowEngineStub for pre-build test packaging." -f $Target, ($candidates -join ", "))
            }
        }
    }

    # For gamma-monolith, bundle sibling AnomalyDX11.exe fallback alongside AnomalyDX11AVX.exe
    if (-not $isStub -and $Target -eq "gamma-monolith" -and $expectedPrimaryName -ieq "AnomalyDX11AVX.exe") {
        $primaryDir = Split-Path -Parent $primarySource
        $dx11Candidates = @(
            (Join-Path $primaryDir "AnomalyDX11.exe"),
            (Join-Path $StandBinDir "AnomalyDX11.exe"),
            "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may\_out\bin\AnomalyDX11.exe",
            "D:\GAMMA-Gamepad-Lab\ports\PORT-G\out\AnomalyDX11.exe"
        )
        foreach ($dx11 in $dx11Candidates) {
            if (Test-Path -LiteralPath $dx11) {
                $additionalExes.Add([PSCustomObject]@{
                    ExeName    = "AnomalyDX11.exe"
                    SourcePath = (Resolve-Path -LiteralPath $dx11).Path
                })
                break
            }
        }
    }

    # Resolve SDL3.dll
    $resolvedSdl = ""
    if (-not [string]::IsNullOrWhiteSpace($SdlDllPath)) {
        if (-not (Test-Path -LiteralPath $SdlDllPath)) {
            throw "SdlDllPath not found: $SdlDllPath"
        }
        $resolvedSdl = (Resolve-Path -LiteralPath $SdlDllPath).Path
    } else {
        $sdlCandidates = New-Object System.Collections.Generic.List[string]
        if ($primarySource) {
            $sdlCandidates.Add((Join-Path (Split-Path -Parent $primarySource) "SDL3.dll"))
        }
        if ($Target -eq "gamma-monolith") {
            $sdlCandidates.Add((Join-Path $StandBinDir "SDL3.dll"))
        } elseif ($Target -eq "gamma-monolith-dlss") {
            $sdlCandidates.Add((Join-Path $DlssStandBin "SDL3.dll"))
        } elseif ($Target -eq "anomaly-vanilla") {
            $sdlCandidates.Add("D:\GAMMA-Gamepad-Lab\ports\PORT-A\out\SDL3.dll")
        }
        $sdlCandidates.Add("D:\GAMMA-Gamepad-Lab\game\bin\SDL3.dll")

        foreach ($sc in $sdlCandidates) {
            if (Test-Path -LiteralPath $sc) {
                $resolvedSdl = (Resolve-Path -LiteralPath $sc).Path
                break
            }
        }
        if (-not $resolvedSdl) {
            throw ("SDL3.dll not found (checked: {0}). Pass -SdlDllPath <path>." -f ($sdlCandidates -join ", "))
        }
    }

    return [PSCustomObject]@{
        ExeName        = $expectedPrimaryName
        SourcePath     = $primarySource
        IsStub         = $isStub
        StubReason     = $stubReason
        AdditionalExes = $additionalExes.ToArray()
        SdlDllPath     = $resolvedSdl
    }
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

    # Try strict UTF-8 decode: multi-byte UTF-8 succeeds here, single-byte CP1251 Cyrillic throws
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
    $dlssBlock = if ($BuildTarget -in @("pbr-dx12-optional", "gamma-monolith-dlss")) {
@"

--------------------------------------------------------------------------------
DLSS / FSR 3 / DX12 BRIDGE COMPONENTS (present in $BuildTarget)
--------------------------------------------------------------------------------
- NVIDIA DLSS SDK (NGX) & NVIDIA Streamline SDK - Copyright (c) NVIDIA
  Corporation. Governed by NVIDIA DLSS / Streamline license terms (see
  THIRD_PARTY\DLSS-LICENSE.txt, Streamline-LICENSE.txt, and
  engine_files\NVIDIA-DLSS-LICENSE.txt).
- AMD FidelityFX SDK / FSR 3 - Copyright (c) Advanced Micro Devices, Inc.
  Licensed under the MIT License (see THIRD_PARTY\FSR3-LICENSE.txt and
  engine_files\AMD-FIDELITYFX-LICENSE.md).
- Microsoft DirectX 12 Agility SDK - Copyright (c) Microsoft Corporation
  (see THIRD_PARTY\AgilitySDK-LICENSE.txt and
  engine_files\D3D12\AGILITY-SDK-LICENSE.txt).
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

2. Simple DirectMedia Layer 3 (SDL3.dll - SDL 3.4.x)
   - Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
   - Licensed under the zlib License (see THIRD_PARTY\SDL3-LICENSE.txt).

3. OpenAL Soft (dynamically linked via Anomaly\bin\soft_oal.dll)
   - Licensed under the GNU Lesser General Public License v2.1 (LGPL-2.1-or-later).
   - Dynamically linked; users may replace soft_oal.dll in Anomaly\bin\ with any
     ABI-compatible x64 OpenAL Soft build (https://github.com/kcat/openal-soft).

4. Libraries Statically Linked in X-Ray Engine Executable
   - LuaJIT 2.x (Copyright (C) 2005-2023 Mike Pall) & Lua 5.1 (PUC-Rio) - MIT License.
   - Luabind (Copyright (c) 2003-2010 Daniel Wallin, Arvid Norberg) - MIT License.
   - Dear ImGui (Copyright (c) 2014-2025 Omar Cornut) - MIT License.
   - Intel oneAPI Threading Building Blocks (oneTBB) / PPL - Apache License 2.0.
   - OpenSSL / SSLeay (xrCore\crypto) - OpenSSL & Original SSLeay Licenses:
     "This product includes cryptographic software written by Eric Young (eay@cryptsoft.com)"
     "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
   - Independent JPEG Group libjpeg 6b:
     "This software is based in part on the work of the Independent JPEG Group."
   - Xiph.Org libogg, libvorbis, libtheora - BSD 3-Clause License.
   - Open Dynamics Engine (ODE, Copyright (c) Russell L. Smith) - BSD 3-Clause License.
   - OPCODE 1.2 (Pierre Terdiman) - Author attribution notice.
   - CxImage (Davide Pizzolato), giflib, NVIDIA Texture Tools (NVTT) - zlib / MIT.
   - StackWalker (Jochen Kalmbach) - BSD 2-Clause License.
   - Unicode ICU Components - Unicode / ICU License.

5. Gamepad UI Icons, Glyphs & Clean-Room Compatibility Adapters
   - Vector Gamepad Diagrams (TheHoodieGuy02) - Creative Commons Zero v1.0 Universal
     (CC0-1.0, see THIRD_PARTY\VectorGamepad-CC0-LICENSE.txt).
   - Steam-Style Gamepad Icon Reference Pack - see THIRD_PARTY\SteamStylePack-LICENSE.txt.
   - Clean-room first-party gamepad glyphs & tactical UI atlases created for this project;
     public Lua API compatibility hooks interoperate with locally installed G.A.M.M.A.
     addons (GAMMA Mags Reloaded, AmmoCheck Enhanced, Quick Action Wheel by HarukaSai,
     Hideout Furniture by Aoldri, PAW by RavenAscendant, Ledge Grabbing by themrdemonized)
     without bundling their proprietary archives.
$dlssBlock
================================================================================
"@
}

function New-CmdLauncherText {
    param(
        [ValidateSet("Install", "Restore")]
        [string]$Action,
        [ValidateSet("ru", "en")]
        [string]$Lang
    )
    return @(
        "@echo off",
        "setlocal",
        "chcp 65001 >nul",
        ("powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0engine_files\engine_helper.ps1"" -Action {0} -Lang {1} %*" -f $Action, $Lang),
        "set ""RC=%ERRORLEVEL%""",
        "echo.",
        "if not defined GP_NO_PAUSE pause",
        "exit /b %RC%"
    ) -join "`r`n"
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host (" BUILD RELEASE - Gamepad At Your Service v{0} [{1}]{2}" -f $Version, $Target, $(if ($DryRun) { " (DRY RUN)" } else { "" })) -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ModSourceDir)) {
    throw "ModSourceDir not found: $ModSourceDir"
}

$helperSrc = Join-Path $PkgToolDir "engine_helper.ps1"
if (-not (Test-Path -LiteralPath $helperSrc)) {
    throw "engine_helper.ps1 not found at: $helperSrc"
}

$engineInfo = Resolve-EnginePackageFiles
Write-Host ("Engine Target : {0} -> {1}" -f $engineInfo.ExeName, $(if ($engineInfo.IsStub) { "STUB ($($engineInfo.StubReason))" } else { $engineInfo.SourcePath }))
foreach ($ax in $engineInfo.AdditionalExes) {
    Write-Host ("Engine Extra  : {0} -> {1}" -f $ax.ExeName, $ax.SourcePath)
}
Write-Host ("SDL3 Runtime  : {0}" -f $engineInfo.SdlDllPath)
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
            SourcePath    = $f.FullName
            RelPath       = $rel
            Category      = $disp.Category
            Action        = $action
            SizeBytes     = $outLen
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

$dlssOverlayRelSet = @{}
if ($Target -eq "gamma-monolith-dlss") {
    if (-not (Test-Path -LiteralPath $DlssExtrasDir)) { throw "DlssExtrasDir not found: $DlssExtrasDir" }
    $extrasResolved = (Resolve-Path -LiteralPath $DlssExtrasDir).Path
    $sss235FlatCandidate = Join-Path (Split-Path -Parent $extrasResolved) "dlss_fomod\sss235\gamedata\shaders\r3\deffer_impl_flat.ps"
    foreach ($f in @(Get-ChildItem -LiteralPath $extrasResolved -Recurse -File | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($extrasResolved.Length + 1)
        if (-not $rel.StartsWith("gamedata\", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        # Match verified may-test-dlss overlay: omit wd_body.vs and prefer SSS 23.5 deffer_impl_flat.ps if present
        if ($rel -ieq "gamedata\shaders\r3\wd_body.vs") { continue }
        $srcToUse = $f.FullName
        if ($rel -ieq "gamedata\shaders\r3\deffer_impl_flat.ps" -and (Test-Path -LiteralPath $sss235FlatCandidate)) {
            $srcToUse = (Resolve-Path -LiteralPath $sss235FlatCandidate).Path
        }
        if ($ForbiddenPbrShaderNames.ContainsKey($f.Name.ToLowerInvariant())) {
            throw "Forbidden closed PBR shader encountered in DLSS overlay: $rel"
        }

        $ext = $f.Extension.ToLowerInvariant()
        $encPlan = if ($ext -in @(".script", ".ltx", ".xml")) { (Convert-GameTextToTargetBytes -SourcePath $srcToUse -RelPath $rel) } else { $null }
        $relNormSlash = ($rel -replace "\\", "/").ToLowerInvariant()
        $dlssOverlayRelSet[$relNormSlash] = $true
        $includedPlan.Add([PSCustomObject]@{
            SourcePath    = $srcToUse
            RelPath       = $rel
            Category      = "dlss_overlay_gamedata"
            Action        = $(if ($null -ne $encPlan) { $encPlan.Action } else { "copy_binary" })
            SizeBytes     = $(if ($null -ne $encPlan) { $encPlan.Bytes.Length } else { (Get-Item -LiteralPath $srcToUse).Length })
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
    Write-Host "`n--- DRY RUN: MO2-READY ARCHIVE PLAN ($ModFolderName\) ---" -ForegroundColor Green
    Write-Host ("  {0}\meta.ini" -f $ModFolderName)
    Write-Host ("  {0}\engine_files\{1} ({2})" -f $ModFolderName, $engineInfo.ExeName, $(if ($engineInfo.IsStub) { "STUB" } else { "$((Get-Item $engineInfo.SourcePath).Length) bytes" }))
    foreach ($ax in $engineInfo.AdditionalExes) {
        Write-Host ("  {0}\engine_files\{1} ({2} bytes)" -f $ModFolderName, $ax.ExeName, (Get-Item $ax.SourcePath).Length)
    }
    Write-Host ("  {0}\engine_files\SDL3.dll ({1} bytes)" -f $ModFolderName, (Get-Item -LiteralPath $engineInfo.SdlDllPath).Length)
    Write-Host ("  {0}\engine_files\engine_helper.ps1" -f $ModFolderName)
    foreach ($item in $includedPlan) {
        Write-Host ("  {0}\{1}  [{2} | {3} | {4} B]" -f $ModFolderName, $item.RelPath, $item.Category, $item.Action, $item.SizeBytes)
    }
    Write-Host ("  {0}\tools\verify.ps1" -f $ModFolderName)
    Write-Host ("  {0}\Установить_движок.cmd, Вернуть_оригинал.cmd, Install_Engine.cmd, Restore_Original.cmd" -f $ModFolderName)
    Write-Host ("  {0}\THIRD_PARTY\*, README-RU.txt, README-EN.txt, THIRD-PARTY-NOTICES.txt, manifest.sha256.json, SHA256SUMS.txt" -f $ModFolderName)
    Write-Host "`nDRY RUN COMPLETE - zero files written." -ForegroundColor Green
    exit 0
}

# ==============================================================================
# Stage Release Directory (MO2-Ready Single Root Folder: GAMMA Gamepad & Tactical UI)
# ==============================================================================
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$OutputDirResolved = (Resolve-Path -LiteralPath $OutputDir).Path
$ArchiveStem = ("Gamepad-At-Your-Service-v{0}-{1}" -f $Version, $Target)
$StageContainer = Join-Path $OutputDirResolved ("_staging_{0}" -f $Target)
$StageRoot = Join-Path $StageContainer $ModFolderName
$ZipPath = Join-Path $OutputDirResolved ("{0}.zip" -f $ArchiveStem)

if (Test-Path -LiteralPath $StageContainer) {
    Remove-Item -LiteralPath $StageContainer -Recurse -Force
}

$DirEngine = Join-Path $StageRoot "engine_files"
$DirTools  = Join-Path $StageRoot "tools"
$DirLic    = Join-Path $StageRoot "THIRD_PARTY"

foreach ($d in @($StageRoot, $DirEngine, $DirTools, $DirLic)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# 1. Populate engine_files\
$stagedExePath = Join-Path $DirEngine $engineInfo.ExeName
if ($engineInfo.IsStub) {
    $stubText = "PENDING_BUILD_STUB: target=$Target version=$Version reason=$($engineInfo.StubReason)`r`nReplace with compiled $($engineInfo.ExeName) before player distribution.`r`n"
    [System.IO.File]::WriteAllText($stagedExePath, $stubText, $Utf8NoBom)
} else {
    Copy-Item -LiteralPath $engineInfo.SourcePath -Destination $stagedExePath -Force
}

$stagedAdditionalExes = New-Object System.Collections.Generic.List[object]
foreach ($ax in $engineInfo.AdditionalExes) {
    $axDst = Join-Path $DirEngine $ax.ExeName
    Copy-Item -LiteralPath $ax.SourcePath -Destination $axDst -Force
    $stagedAdditionalExes.Add([ordered]@{
        exe_name     = $ax.ExeName
        package_path = ("engine_files/{0}" -f $ax.ExeName)
        size_bytes   = (Get-Item -LiteralPath $axDst).Length
        sha256       = (Get-FileHash -LiteralPath $axDst -Algorithm SHA256).Hash.ToUpperInvariant()
    })
}

$stagedSdlPath = Join-Path $DirEngine "SDL3.dll"
Copy-Item -LiteralPath $engineInfo.SdlDllPath -Destination $stagedSdlPath -Force

if ($Target -eq "gamma-monolith-dlss") {
    $dlssBinRoot = (Resolve-Path -LiteralPath $DlssStandBin).Path
    $dlssBinFiles = @(
        "nvngx_dlss.dll",
        "amd_fidelityfx_framegeneration_dx12.dll",
        "amd_fidelityfx_loader_dx12.dll",
        "amd_fidelityfx_upscaler_dx12.dll",
        "AMD-FIDELITYFX-LICENSE.md",
        "NVIDIA-DLSS-LICENSE.txt",
        "D3D12\D3D12Core.dll",
        "D3D12\AGILITY-SDK-LICENSE.txt",
        "streamline\nvngx_dlssg.dll",
        "streamline\sl.common.dll",
        "streamline\sl.dlss_g.dll",
        "streamline\sl.interposer.dll",
        "streamline\sl.pcl.dll",
        "streamline\sl.reflex.dll",
        "streamline\RUNTIME.txt",
        "streamline\STREAMLINE-LICENSE.txt"
    )
    foreach ($rel in $dlssBinFiles) {
        $src = Join-Path $dlssBinRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { throw "DLSS runtime file missing: $src" }
        $dst = Join-Path $DirEngine $rel
        $dstParent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstParent)) {
            New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$helperText = [System.IO.File]::ReadAllText($helperSrc, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $DirEngine "engine_helper.ps1"), $helperText, $Utf8Bom)

# 2. Populate THIRD-PARTY-NOTICES.txt & THIRD_PARTY\
$noticesText = (New-ThirdPartyNoticesText -BuildTarget $Target -RelVersion $Version) -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $StageRoot "THIRD-PARTY-NOTICES.txt"), $noticesText, $Utf8NoBom)

$licenseSources = @(
    @{ Src = "D:\GAMMA-Gamepad-Lab\ports\PORT-G\src\License.txt"; Fallback = "D:\GAMMA-Gamepad-Lab\build\engine\License.txt"; Dst = "License-XRay-GSC.txt" },
    @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\src\3rd party\SDL3\LICENSE.txt"; Fallback = "D:\GAMMA-Gamepad-Lab\ports\PORT-MT\wt\may\src\3rd party\SDL3\LICENSE.txt"; Dst = "SDL3-LICENSE.txt" },
    @{ Src = (Join-Path $RepoRoot "assets\third_party\vector-gamepad\LICENSE.txt"); Fallback = ""; Dst = "VectorGamepad-CC0-LICENSE.txt" },
    @{ Src = (Join-Path $RepoRoot "assets\gamepad_icons\steam_style_pack\LICENSE"); Fallback = ""; Dst = "SteamStylePack-LICENSE.txt" }
)
if ($Target -in @("pbr-dx12-optional", "gamma-monolith-dlss")) {
    $licenseSources += @(
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\DLSS\LICENSE.txt"; Fallback = (Join-Path $DlssStandBin "NVIDIA-DLSS-LICENSE.txt"); Dst = "DLSS-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\Streamline\LICENSE.txt"; Fallback = (Join-Path $DlssStandBin "streamline\STREAMLINE-LICENSE.txt"); Dst = "Streamline-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\FSR3\LICENSE.txt"; Fallback = (Join-Path $DlssStandBin "AMD-FIDELITYFX-LICENSE.md"); Dst = "FSR3-LICENSE.txt" },
        @{ Src = "D:\GAMMA-Gamepad-Lab\build\engine\sdk\AgilitySDK\LICENSE.txt"; Fallback = (Join-Path $DlssStandBin "D3D12\AGILITY-SDK-LICENSE.txt"); Dst = "AgilitySDK-LICENSE.txt" }
    )
}
foreach ($ls in $licenseSources) {
    $srcUse = if (Test-Path -LiteralPath $ls.Src) { $ls.Src } elseif ($ls.Fallback -and (Test-Path -LiteralPath $ls.Fallback)) { $ls.Fallback } else { "" }
    if ($srcUse) {
        Copy-Item -LiteralPath $srcUse -Destination (Join-Path $DirLic $ls.Dst) -Force
    }
}

# 3. Populate meta.ini & gamedata\
$metaIni = @"
[General]
gameName=stalkeranomaly
modid=0
version=$Version
newestVersion=$Version
category="User Interface,"
installationFile=$ArchiveStem.zip
comments="Gamepad At Your Service ($Target) - place at the VERY BOTTOM of MO2"
notes="Open mod folder and run Install_Engine.cmd or Установить_движок.cmd to update Anomaly\bin"
"@ -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $StageRoot "meta.ini"), $metaIni, $Utf8NoBom)

foreach ($item in $includedPlan) {
    $dstPath = Join-Path $StageRoot $item.RelPath
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

# 4. Populate .cmd one-click helpers, READMEs & tools\verify.ps1
$cmdDefs = @(
    @{ Name = "Установить_движок.cmd"; Action = "Install"; Lang = "ru" },
    @{ Name = "Вернуть_оригинал.cmd";  Action = "Restore"; Lang = "ru" },
    @{ Name = "Install_Engine.cmd";    Action = "Install"; Lang = "en" },
    @{ Name = "Restore_Original.cmd";  Action = "Restore"; Lang = "en" }
)
foreach ($cd in $cmdDefs) {
    $cmdContent = (New-CmdLauncherText -Action $cd.Action -Lang $cd.Lang) + "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $StageRoot $cd.Name), $cmdContent, [System.Text.Encoding]::ASCII)
}

$readmeRuText = [System.IO.File]::ReadAllText((Join-Path $PkgToolDir "README-RU.txt"), [System.Text.Encoding]::UTF8)
$readmeEnText = [System.IO.File]::ReadAllText((Join-Path $PkgToolDir "README-EN.txt"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $StageRoot "README-RU.txt"), ($readmeRuText -replace "`r?`n", "`r`n"), $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $StageRoot "README-EN.txt"), ($readmeEnText -replace "`r?`n", "`r`n"), $Utf8NoBom)

$verifySrcText = [System.IO.File]::ReadAllText((Join-Path $PkgToolDir "verify.ps1"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $DirTools "verify.ps1"), $verifySrcText, $Utf8Bom)

# 5. Compute SHA-256 Manifest across all staged payload files inside $StageRoot
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
    $relLower = $relSlash.ToLowerInvariant()
    $hash = (Get-FileHash -LiteralPath $sf.FullName -Algorithm SHA256).Hash.ToUpperInvariant()

    $cat = "docs_and_tools"
    $gdRel = ""
    $binRel = ""

    if ($relLower -eq "meta.ini") {
        $cat = "mo2_meta"
    } elseif ($relLower.StartsWith("gamedata/")) {
        $gdRel = $relSlash
        if ($gammaOverrideNormSet.ContainsKey($relLower)) {
            $cat = "gamma_screen_override"
        } elseif ($dlssOverlayRelSet.ContainsKey($relLower)) {
            $cat = "dlss_overlay_gamedata"
        } else {
            $cat = "mod_gamedata"
        }
    } elseif ($relLower.StartsWith("engine_files/")) {
        if ($relLower -eq "engine_files/engine_helper.ps1") {
            $cat = "docs_and_tools"
        } else {
            $cat = "anomaly_bin"
            $binRel = $relSlash.Substring("engine_files/".Length)
        }
    } elseif ($relLower.StartsWith("third_party/") -or $relLower -eq "third-party-notices.txt") {
        $cat = "license"
    }

    $manifestEntries.Add([ordered]@{
        path              = $relSlash
        gamedata_rel_path = $gdRel
        bin_rel_path      = $binRel
        category          = $cat
        size_bytes        = $sf.Length
        sha256            = $hash
    })
    $shaSumsLines.Add(("{0}  {1}" -f $hash.ToLowerInvariant(), $relSlash))
}

$exeHash = (Get-FileHash -LiteralPath $stagedExePath -Algorithm SHA256).Hash.ToUpperInvariant()
$sdlHash = (Get-FileHash -LiteralPath $stagedSdlPath -Algorithm SHA256).Hash.ToUpperInvariant()

$manifestObj = [ordered]@{
    schema_version  = 2
    package_name    = "Gamepad-At-Your-Service"
    version         = $Version
    target          = $Target
    is_optional_pbr = ($Target -eq "pbr-dx12-optional")
    built_at        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    mod_folder_name = $ModFolderName
    file_marker     = "GAYS_REL1_20261114"
    engine          = [ordered]@{
        exe_name        = $engineInfo.ExeName
        package_path    = ("engine_files/{0}" -f $engineInfo.ExeName)
        size_bytes      = (Get-Item -LiteralPath $stagedExePath).Length
        sha256          = $exeHash
        is_stub         = $engineInfo.IsStub
        stub_reason     = $engineInfo.StubReason
        additional_exes = $stagedAdditionalExes.ToArray()
    }
    sdl3            = [ordered]@{
        dll_name     = "SDL3.dll"
        package_path = "engine_files/SDL3.dll"
        size_bytes   = (Get-Item -LiteralPath $stagedSdlPath).Length
        sha256       = $sdlHash
    }
    counts          = [ordered]@{
        total_files   = $manifestEntries.Count
        gamedata_only = @($manifestEntries | Where-Object { $_.category -in @("mod_gamedata", "gamma_screen_override", "dlss_overlay_gamedata") }).Count
        engine_bin    = @($manifestEntries | Where-Object { $_.category -eq "anomaly_bin" }).Count
        excluded      = $excludedPlan.Count
        reencoded     = $reencodedCount
    }
    files           = $manifestEntries
}

$manifestJson = $manifestObj | ConvertTo-Json -Depth 6
$shaSumsText = ($shaSumsLines -join "`r`n") + "`r`n"

[System.IO.File]::WriteAllText((Join-Path $StageRoot "manifest.sha256.json"), $manifestJson, $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $StageRoot "SHA256SUMS.txt"), $shaSumsText, $Utf8NoBom)

# 6. Post-stage self-verification via tools\verify.ps1 -PackageRoot
Write-Host "`nRunning read-only package verification gate..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $DirTools "verify.ps1") -PackageRoot $StageRoot -Lang ru
$verExit = $LASTEXITCODE
if ($verExit -eq 1) {
    throw "Post-stage verify.ps1 FAILED (exit code 1)!"
}

# 7. Compress .zip Archive (UTF-8 filenames + standard forward slashes for MO2)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

$containerNorm = (Resolve-Path -LiteralPath $StageContainer).Path
$zipStream = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create, [System.Text.Encoding]::UTF8)
try {
    $allZipFiles = @(Get-ChildItem -LiteralPath $containerNorm -Recurse -File | Sort-Object FullName)
    foreach ($zf in $allZipFiles) {
        $entryName = $zf.FullName.Substring($containerNorm.Length + 1) -replace "\\", "/"
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zipStream,
            $zf.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
    }
} finally {
    $zipStream.Dispose()
}

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
