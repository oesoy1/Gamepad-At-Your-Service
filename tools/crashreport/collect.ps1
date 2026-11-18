<#
.SYNOPSIS
    GAMMA Gamepad & Tactical UI — Crash & Diagnostic Report Collector (CRASH1).
    СТРОГО ТОЛЬКО ЧТЕНИЕ ИГРОВЫХ ФАЙЛОВ / STRICTLY READ-ONLY FOR GAME & MO2 FILES.

.DESCRIPTION
    Collects all logs, minidumps (within size limit), gamepad error reports,
    gamepad profile/bindings/layout, MO2 modlist, game/engine version metadata,
    connected gamepad devices, and basic system specs into a sanitized ZIP archive:
      Documents\GAMMA-Gamepad-report-<YYYYMMDD-HHMMSS>.zip

    Personal data sanitization:
      Replaces Windows username, user profile paths (C:\Users\<name>), computer name,
      and username embedded in xray_<user>.log / .bkp / .mdmp filenames with <USER> / <PC>.

    Target baseline (D64, 2026-11-14):
      Primary: Original G.A.M.M.A. engine (xray-monolith, AnomalyDX11AVX.exe / AnomalyDX11.exe)
               and Original Anomaly.
      Optional: PBR + DX12 + DLSS custom build (AnomalyDX12.exe).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GameRoot = "",

    [Parameter(Mandatory = $false)]
    [string]$AppDataRoot = "",

    [Parameter(Mandatory = $false)]
    [string]$Mo2Root = "",

    [Parameter(Mandatory = $false)]
    [string]$ProfileName = "",

    [Parameter(Mandatory = $false)]
    [string]$ModName = "GAMMA Gamepad & Tactical UI",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [int]$MaxZipSizeMB = 25,

    [Parameter(Mandatory = $false)]
    [int]$MaxLogFileMB = 10,

    [Parameter(Mandatory = $false)]
    [bool]$IncludeMinidump = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("both", "ru", "en")]
    [string]$Lang = "both",

    [Parameter(Mandatory = $false)]
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$Cp1251 = [System.Text.Encoding]::GetEncoding(1251)

# Known stock (unmodded) executable SHA-256 hashes (uppercase) from tools/package/verify.ps1
$KnownStockExeHashes = @{
    "F48B423AB48E2A80E8A741E6AD92608DBF115831678D2F4A53F04D3DBE44AFF7" = "Stock X-Ray Monolith MT 2026.10.11 (G.A.M.M.A. AnomalyDX11AVX.exe, NO gamepad module)"
    "ADE57887F93CA95E9398DA60B374035B50E4C38295B9802A6F89BC33A0394BC"  = "Stock X-Ray Monolith MT 2026.05.15 (G.A.M.M.A. AnomalyDX11AVX.exe, NO gamepad module)"
    "C434471FBFFF5409442847119B07B02B22409F64A2F1FEDFFE802259A118D2AC" = "Stock PBR test AnomalyDX11AVX.exe (NO gamepad module)"
    "F4C892E798191C31FD6C4E3EBE5D0157E0047D7E25A2A59D9ED0C54377C9E3BD" = "Stock AnomalyDX11.exe (NO gamepad module)"
    "93E2A7D68589488164727A98769A13E77958854BF18B87A5D414BE283EC74281" = "Stock PBR AnomalyDX12.exe (NO gamepad module)"
}

function Write-Bi {
    param(
        [string]$Ru,
        [string]$En,
        [string]$Color = "Gray"
    )
    switch ($Lang) {
        "ru" { Write-Host $Ru -ForegroundColor $Color }
        "en" { Write-Host $En -ForegroundColor $Color }
        default {
            Write-Host $Ru -ForegroundColor $Color
            if (-not [string]::IsNullOrWhiteSpace($En) -and $En -ne $Ru) {
                Write-Host ("  EN: {0}" -f $En) -ForegroundColor DarkGray
            }
        }
    }
}

function Convert-ByteArrayIniValue {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    $v = $Raw.Trim()
    if ($v -match '^@ByteArray\((.*)\)$') {
        $v = $Matches[1]
    }
    $v = $v -replace '\\\\', '\'
    $v = $v -replace '/', '\'
    return $v.Trim()
}

function Parse-ModOrganizerIni {
    param([string]$IniPath)
    $result = [ordered]@{
        ini_path           = $IniPath
        game_path          = ""
        selected_profile   = ""
        base_directory     = ""
        profiles_directory = ""
        mods_directory     = ""
    }
    if (-not (Test-Path -LiteralPath $IniPath)) { return $result }
    $mo2Dir = Split-Path -Parent $IniPath
    $lines = [System.IO.File]::ReadAllLines($IniPath, $Utf8NoBom)
    foreach ($line in $lines) {
        if ($line -match '^\s*gamePath\s*=\s*(.+)$') {
            $result.game_path = Convert-ByteArrayIniValue $Matches[1]
        } elseif ($line -match '^\s*selected_profile\s*=\s*(.+)$') {
            $result.selected_profile = Convert-ByteArrayIniValue $Matches[1]
        } elseif ($line -match '^\s*base_directory\s*=\s*(.+)$') {
            $result.base_directory = Convert-ByteArrayIniValue $Matches[1]
        } elseif ($line -match '^\s*profiles_directory\s*=\s*(.+)$') {
            $result.profiles_directory = Convert-ByteArrayIniValue $Matches[1]
        } elseif ($line -match '^\s*mods_directory\s*=\s*(.+)$') {
            $result.mods_directory = Convert-ByteArrayIniValue $Matches[1]
        }
    }
    $baseDir = if ($result.base_directory) { $result.base_directory -replace '%BASE_DIR%', $mo2Dir } else { $mo2Dir }
    if (-not $result.profiles_directory) {
        $result.profiles_directory = Join-Path $baseDir "profiles"
    } else {
        $result.profiles_directory = $result.profiles_directory -replace '%BASE_DIR%', $baseDir
    }
    if (-not $result.mods_directory) {
        $result.mods_directory = Join-Path $baseDir "mods"
    } else {
        $result.mods_directory = $result.mods_directory -replace '%BASE_DIR%', $baseDir
    }
    return $result
}

function Resolve-PathsAuto {
    $candidatesSearchRoots = New-Object System.Collections.Generic.List[string]
    $cwd = (Get-Location).Path
    foreach ($start in @($PSScriptRoot, $cwd)) {
        if ([string]::IsNullOrWhiteSpace($start)) { continue }
        $cur = $start
        for ($d = 0; $d -lt 5 -and -not [string]::IsNullOrWhiteSpace($cur); $d++) {
            if (-not $candidatesSearchRoots.Contains($cur)) {
                $candidatesSearchRoots.Add($cur)
            }
            $parent = Split-Path -Parent $cur
            if ($parent -eq $cur) { break }
            $cur = $parent
        }
    }

    # Check standard install paths only as fallbacks after script/cwd ancestors
    foreach ($std in @("D:\Stalker\GAMMA", "D:\Stalker\Anomaly", "C:\GAMMA", "D:\GAMMA", "C:\Anomaly", "D:\Anomaly", "D:\GAMMA-Gamepad-Lab\game")) {
        if ((Test-Path -LiteralPath $std) -and -not $candidatesSearchRoots.Contains($std)) {
            $candidatesSearchRoots.Add($std)
        }
    }

    $resolvedMo2 = $Mo2Root
    $resolvedGame = $GameRoot
    $mo2Meta = $null

    if ([string]::IsNullOrWhiteSpace($resolvedMo2)) {
        foreach ($r in $candidatesSearchRoots) {
            $ini = Join-Path $r "ModOrganizer.ini"
            if (Test-Path -LiteralPath $ini) {
                $resolvedMo2 = $r
                break
            }
            # Also check sibling GAMMA folder if starting from Anomaly folder
            $parent = Split-Path -Parent $r
            if ($parent) {
                foreach ($sibName in @("GAMMA", "MO2", "ModOrganizer")) {
                    $sibIni = Join-Path (Join-Path $parent $sibName) "ModOrganizer.ini"
                    if (Test-Path -LiteralPath $sibIni) {
                        $resolvedMo2 = Join-Path $parent $sibName
                        break
                    }
                }
            }
            if ($resolvedMo2) { break }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedMo2)) {
        $iniPath = Join-Path $resolvedMo2 "ModOrganizer.ini"
        if (Test-Path -LiteralPath $iniPath) {
            $mo2Meta = Parse-ModOrganizerIni -IniPath $iniPath
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedGame)) {
        # First check direct ancestors of script/cwd (prefer local folder if user copied script into game folder)
        foreach ($r in @($PSScriptRoot, $cwd)) {
            $cur = $r
            for ($d = 0; $d -lt 5 -and -not [string]::IsNullOrWhiteSpace($cur); $d++) {
                if (Test-Path -LiteralPath (Join-Path $cur "fsgame.ltx")) {
                    $resolvedGame = $cur
                    break
                }
                $cur = Split-Path -Parent $cur
            }
            if ($resolvedGame) { break }
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedGame) -and $mo2Meta -and $mo2Meta.game_path) {
        if (Test-Path -LiteralPath $mo2Meta.game_path) {
            $resolvedGame = $mo2Meta.game_path
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedGame)) {
        foreach ($r in $candidatesSearchRoots) {
            if (Test-Path -LiteralPath (Join-Path $r "fsgame.ltx")) {
                $resolvedGame = $r
                break
            }
            $anomSub = Join-Path $r "Anomaly"
            if (Test-Path -LiteralPath (Join-Path $anomSub "fsgame.ltx")) {
                $resolvedGame = $anomSub
                break
            }
        }
    }

    # If still no MO2 found, inspect sibling of resolvedGame
    if ([string]::IsNullOrWhiteSpace($resolvedMo2) -and -not [string]::IsNullOrWhiteSpace($resolvedGame)) {
        $gParent = Split-Path -Parent $resolvedGame
        if ($gParent) {
            foreach ($sibName in @("GAMMA", "MO2", "ModOrganizer")) {
                $sibPath = Join-Path $gParent $sibName
                if (Test-Path -LiteralPath (Join-Path $sibPath "ModOrganizer.ini")) {
                    $resolvedMo2 = $sibPath
                    $mo2Meta = Parse-ModOrganizerIni -IniPath (Join-Path $sibPath "ModOrganizer.ini")
                    break
                }
            }
        }
    }

    return [PSCustomObject]@{
        GameRoot = $resolvedGame
        Mo2Root  = $resolvedMo2
        Mo2Meta  = $mo2Meta
    }
}

function Parse-FsGameLtx {
    param(
        [string]$FsGamePath,
        [string]$GameRootPath
    )
    $vars = @{
        '$fs_root$' = ($GameRootPath.TrimEnd('\', '/') + '\')
    }
    if (-not (Test-Path -LiteralPath $FsGamePath)) {
        $app = Join-Path $GameRootPath "appdata"
        return @{
            '$fs_root$'       = $vars['$fs_root$']
            '$app_data_root$' = $app.TrimEnd('\', '/') + '\'
            '$logs$'          = (Join-Path $app "logs").TrimEnd('\', '/') + '\'
            '$game_data$'     = (Join-Path $GameRootPath "gamedata").TrimEnd('\', '/') + '\'
        }
    }

    $rawEntries = New-Object System.Collections.Generic.List[object]
    foreach ($line in [System.IO.File]::ReadAllLines($FsGamePath, $Cp1251)) {
        $clean = ($line -replace ';.*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($clean -match '^(\$[A-Za-z0-9_]+\$)\s*=\s*(.+)$') {
            $key = $Matches[1].Trim()
            $parts = $Matches[2] -split '\|'
            if ($parts.Count -ge 3) {
                $rootSpec = $parts[2].Trim()
                $addSpec  = if ($parts.Count -ge 4) { $parts[3].Trim() } else { "" }
                $rawEntries.Add([PSCustomObject]@{
                    Key  = $key
                    Root = $rootSpec
                    Add  = $addSpec
                })
            }
        }
    }

    # Resolve iteratively to handle out-of-order references
    for ($pass = 0; $pass -lt 4; $pass++) {
        foreach ($e in $rawEntries) {
            $r = $e.Root -replace '/', '\'
            foreach ($k in @($vars.Keys)) {
                if ($r.StartsWith($k, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $r = $vars[$k] + $r.Substring($k.Length)
                    break
                }
            }
            if ($r -match '^\$[A-Za-z0-9_]+\$') { continue }
            $add = ($e.Add -replace '/', '\').TrimStart('\')
            $combined = if ([string]::IsNullOrWhiteSpace($add)) { $r } else { Join-Path $r $add }
            $vars[$e.Key] = $combined.TrimEnd('\', '/') + '\'
        }
    }

    if (-not $vars.ContainsKey('$app_data_root$')) {
        $vars['$app_data_root$'] = (Join-Path $GameRootPath "appdata").TrimEnd('\', '/') + '\'
    }
    if (-not $vars.ContainsKey('$logs$')) {
        $vars['$logs$'] = (Join-Path $vars['$app_data_root$'] "logs").TrimEnd('\', '/') + '\'
    }
    if (-not $vars.ContainsKey('$game_data$')) {
        $vars['$game_data$'] = (Join-Path $GameRootPath "gamedata").TrimEnd('\', '/') + '\'
    }
    return $vars
}

function Get-PeInfo {
    param([string]$FilePath)
    $info = [ordered]@{
        name               = [System.IO.Path]::GetFileName($FilePath)
        size_bytes         = (Get-Item -LiteralPath $FilePath).Length
        last_write_utc     = (Get-Item -LiteralPath $FilePath).LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        sha256             = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToUpperInvariant()
        pe_timestamp_utc   = ""
        imports_sdl3       = $false
        imports_dx12       = $false
        imported_dlls      = @()
        classification     = "unknown"
    }

    if ($KnownStockExeHashes.ContainsKey($info.sha256)) {
        $info.classification = $KnownStockExeHashes[$info.sha256]
    }

    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $br = New-Object System.IO.BinaryReader($fs)
    try {
        if ($fs.Length -lt 128) { return $info }
        if ($br.ReadUInt16() -ne 0x5A4D) { return $info }
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        if ($peOffset -lt 0 -or ($peOffset + 24) -gt $fs.Length) { return $info }
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { return $info }

        $null = $br.ReadUInt16() # Machine
        $numSections = $br.ReadUInt16()
        $timeStamp = $br.ReadUInt32()
        $dtEpoch = [DateTimeOffset]::FromUnixTimeSeconds([int64]$timeStamp)
        $info.pe_timestamp_utc = $dtEpoch.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $fs.Position += 8 # PointerToSymbolTable + NumberOfSymbols
        $sizeOfOptHeader = $br.ReadUInt16()
        $null = $br.ReadUInt16() # Characteristics

        $optHeaderStart = $fs.Position
        $magic = $br.ReadUInt16()
        if ($magic -eq 0x20B) {
            $importDirOffset = $optHeaderStart + 112 + 8
        } elseif ($magic -eq 0x10B) {
            $importDirOffset = $optHeaderStart + 96 + 8
        } else {
            return $info
        }

        $fs.Position = $importDirOffset
        $importRva = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        if ($importRva -eq 0) { return $info }

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

        $impOffset = -1
        foreach ($s in $sections) {
            if ($importRva -ge $s.VirtualAddress -and $importRva -lt ($s.VirtualAddress + $s.Span)) {
                $impOffset = ($importRva - $s.VirtualAddress) + $s.RawPointer
                break
            }
        }
        if ($impOffset -lt 0) { return $info }

        $dllNames = New-Object System.Collections.Generic.List[string]
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

            $nameOff = -1
            foreach ($s in $sections) {
                if ($nameRva -ge $s.VirtualAddress -and $nameRva -lt ($s.VirtualAddress + $s.Span)) {
                    $nameOff = ($nameRva - $s.VirtualAddress) + $s.RawPointer
                    break
                }
            }
            if ($nameOff -ge 0 -and $nameOff -lt $fs.Length) {
                $fs.Position = $nameOff
                $bytes = New-Object System.Collections.Generic.List[byte]
                while ($fs.Position -lt $fs.Length) {
                    $b = $br.ReadByte()
                    if ($b -eq 0) { break }
                    $bytes.Add($b)
                }
                $dll = [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
                if ($dll) { $dllNames.Add($dll) }
            }
            $idx++
        }

        $info['imported_dlls'] = @($dllNames.ToArray())
        $info['imports_sdl3'] = (@($dllNames | Where-Object { $_ -ieq "SDL3.dll" }).Count -gt 0)
        $info['imports_dx12'] = (@($dllNames | Where-Object { $_ -imatch '^d3d12\.dll$' }).Count -gt 0)

        if ($info.classification -eq "unknown") {
            if ($info.imports_sdl3) {
                if ($info.name -imatch 'DX12' -or $info.imports_dx12) {
                    $info.classification = "Modded Gamepad Engine (Optional PBR/DX12 Build, SDL3 linked)"
                } elseif ($info.name -imatch 'DX11') {
                    $info.classification = "Modded Gamepad Engine (Primary G.A.M.M.A./Anomaly DX11 Build, SDL3 linked)"
                } else {
                    $info.classification = "Modded Gamepad Engine (SDL3 linked)"
                }
            } else {
                $info.classification = "Unpatched/Unknown Engine (SDL3.dll NOT imported)"
            }
        }
    } finally {
        $br.Close()
        $fs.Close()
    }
    return $info
}

function Build-SensitiveTokens {
    param([string[]]$ExtraUserNames)
    $userSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $pcSet   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $stopWords = @(
        "user", "users", "admin", "administrator", "public", "default", "game", "games",
        "stalker", "gamma", "anomaly", "xray", "logs", "log", "appdata", "mods", "bin",
        "temp", "tmp", "desktop", "documents", "windows", "program", "test", "player"
    )

    $rawUserCandidates = @(
        $env:USERNAME,
        [Environment]::UserName,
        $(if ($env:USERPROFILE) { [System.IO.Path]::GetFileName($env:USERPROFILE.TrimEnd('\', '/')) } else { "" })
    )
    if ($ExtraUserNames) {
        $rawUserCandidates += $ExtraUserNames
    }
    foreach ($u in $rawUserCandidates) {
        if ([string]::IsNullOrWhiteSpace($u)) { continue }
        $t = $u.Trim()
        if ($t.Length -ge 2) {
            [void]$userSet.Add($t)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        $pc = $env:COMPUTERNAME.Trim()
        if ($pc.Length -ge 2 -and ($stopWords -notcontains $pc.ToLowerInvariant())) {
            [void]$pcSet.Add($pc)
        }
    }

    $strictUsers = @($userSet | Sort-Object Length -Descending)
    $safeWordUsers = @($strictUsers | Where-Object { $_.Length -ge 3 -and ($stopWords -notcontains $_.ToLowerInvariant()) })

    return [PSCustomObject]@{
        AllUsers      = $strictUsers
        SafeWordUsers = $safeWordUsers
        Computers     = @($pcSet | Sort-Object Length -Descending)
    }
}

function Protect-PersonalData {
    param(
        [string]$Text,
        $Tokens
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $out = $Text

    # 1. Windows user profile folder patterns (C:\Users\<name>, C:\Пользователи\<name>, C:/Users/<name>)
    $out = [regex]::Replace(
        $out,
        '(?i)([A-Za-z]:[\\/]+(?:Users|Пользователи|Documents and Settings)[\\/]+)([^\\/\r\n"''<>|\s]+)',
        '${1}<USER>'
    )

    # 2. Exact user paths from environment if non-standard profile folder
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $leaf = [System.IO.Path]::GetFileName($env:USERPROFILE.TrimEnd('\', '/'))
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            $out = [regex]::Replace($out, "(?i)$([regex]::Escape($leaf))(?=[\\/])", "<USER>")
        }
    }

    # 3. X-Ray filenames/patterns: xray_<user>.log / xray_<user>.bkp / xray_<user>_...mdmp / ss_<user>_...
    foreach ($u in $Tokens.AllUsers) {
        $esc = [regex]::Escape($u)
        $out = [regex]::Replace($out, "(?i)\bxray_$esc(?=[_\.])", "xray_<USER>")
        $out = [regex]::Replace($out, "(?i)\bss_$esc(?=[_\.])", "ss_<USER>")
        $out = [regex]::Replace($out, "(?i)([\\/]+)$esc([\\/]+)", '${1}<USER>${2}')
        $out = [regex]::Replace($out, "(?i)([\\/]+)$esc$", '${1}<USER>')
        $out = [regex]::Replace($out, "(?i)(\bUser\s*[:=]\s*)$esc\b", '${1}<USER>')
        $out = [regex]::Replace($out, "(?i)(\bUserName\s*[:=]\s*)$esc\b", '${1}<USER>')
    }

    # 4. Safe non-ambiguous usernames everywhere (including inside save names like "stalker - autosave")
    foreach ($u in $Tokens.SafeWordUsers) {
        $esc = [regex]::Escape($u)
        $out = [regex]::Replace($out, "(?i)(?<![A-Za-z0-9_])$esc(?![A-Za-z0-9_])", "<USER>")
    }

    # 5. Computer name
    foreach ($pc in $Tokens.Computers) {
        $esc = [regex]::Escape($pc)
        $out = [regex]::Replace($out, "(?i)(?<![A-Za-z0-9_])$esc(?![A-Za-z0-9_])", "<PC>")
    }

    return $out
}

function Protect-FileName {
    param(
        [string]$FileName,
        $Tokens
    )
    $res = $FileName
    foreach ($u in $Tokens.AllUsers) {
        $esc = [regex]::Escape($u)
        $res = [regex]::Replace($res, "(?i)(?:^|(?<=[/\\]))xray_$esc(?=[_\.])", "xray_USER")
        $res = [regex]::Replace($res, "(?i)(?:^|(?<=[/\\]))ss_$esc(?=[_\.])", "ss_USER")
    }
    foreach ($u in $Tokens.SafeWordUsers) {
        $esc = [regex]::Escape($u)
        $res = [regex]::Replace($res, "(?i)$esc", "USER")
    }
    foreach ($pc in $Tokens.Computers) {
        $esc = [regex]::Escape($pc)
        $res = [regex]::Replace($res, "(?i)$esc", "PC")
    }
    return $res
}

function Read-TextSmart {
    param([string]$FilePath)
    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $len = [int]$fs.Length
        $bytes = New-Object byte[] $len
        $read = 0
        while ($read -lt $len) {
            $n = $fs.Read($bytes, $read, $len - $read)
            if ($n -le 0) { break }
            $read += $n
        }
    } finally {
        $fs.Close()
    }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return $Utf8NoBom.GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        return $Utf8Strict.GetString($bytes)
    } catch {
        return $Cp1251.GetString($bytes)
    }
}

function Truncate-LogTextIfNeeded {
    param(
        [string]$Text,
        [int]$MaxBytes
    )
    $curBytes = $Utf8NoBom.GetByteCount($Text)
    if ($curBytes -le $MaxBytes) {
        return [PSCustomObject]@{ Text = $Text; Truncated = $false; OriginalBytes = $curBytes }
    }
    $lines = $Text -split "\r?\n"
    $headCount = [Math]::Min(350, $lines.Count)
    $head = ($lines[0..($headCount - 1)] -join "`r`n")
    $budgetTail = [Math]::Max(65536, $MaxBytes - $Utf8NoBom.GetByteCount($head) - 512)

    $tailLines = New-Object System.Collections.Generic.List[string]
    $acc = 0
    for ($i = $lines.Count - 1; $i -ge $headCount; $i--) {
        $lineBytes = $Utf8NoBom.GetByteCount($lines[$i]) + 2
        if (($acc + $lineBytes) -gt $budgetTail) { break }
        $tailLines.Add($lines[$i])
        $acc += $lineBytes
    }
    $tailLines.Reverse()
    $marker = "`r`n`r`n[... TRUNCATED BY CRASH REPORT COLLECTOR: original_utf8_bytes=$curBytes, kept head=$headCount lines + tail=$($tailLines.Count) lines ...]`r`n`r`n"
    return [PSCustomObject]@{
        Text          = $head + $marker + ($tailLines -join "`r`n")
        Truncated     = $true
        OriginalBytes = $curBytes
    }
}

function Add-ZipTextEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$Content
    )
    $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $writer = New-Object System.IO.StreamWriter($stream, $Utf8NoBom)
    try {
        $writer.Write($Content)
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Add-ZipBinaryEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$SourcePath
    )
    $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $dst = $entry.Open()
    $src = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $src.CopyTo($dst)
    } finally {
        $src.Dispose()
        $dst.Dispose()
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
Write-Bi -Ru "========================================================================" -En "========================================================================" -Color White
Write-Bi -Ru " GAMMA Gamepad & Tactical UI — СБОР ОТЧЁТА О ВЫЛЕТЕ / CRASH REPORT" -En " GAMMA Gamepad & Tactical UI — CRASH REPORT COLLECTOR" -Color White
Write-Bi -Ru " Режим: ТОЛЬКО ЧТЕНИЕ игры. Личные имена (<USER>) удаляются." -En " Mode: READ-ONLY for game files. Personal usernames (<USER>) are stripped." -Color DarkGray
Write-Bi -Ru "========================================================================" -En "========================================================================" -Color White

$resolved = Resolve-PathsAuto
$effGameRoot = $resolved.GameRoot
$effMo2Root  = $resolved.Mo2Root
$mo2Meta     = $resolved.Mo2Meta

if ([string]::IsNullOrWhiteSpace($effGameRoot) -or -not (Test-Path -LiteralPath $effGameRoot)) {
    Write-Bi `
        -Ru "ОШИБКА: Не удалось автоматически найти папку игры Anomaly (с файлом fsgame.ltx)." `
        -En "ERROR: Could not auto-detect the Anomaly game folder (containing fsgame.ltx)." `
        -Color Red
    Write-Bi `
        -Ru "Подсказка: запустите скрипт с параметром -GameRoot ""C:\Путь\к\Anomaly"" -Mo2Root ""C:\Путь\к\GAMMA""" `
        -En "Hint: run with -GameRoot ""C:\Path\To\Anomaly"" -Mo2Root ""C:\Path\To\GAMMA""" `
        -Color Yellow
    if (-not $NoPause) { Read-Host "Press Enter to exit / Нажмите Enter для выхода" | Out-Null }
    exit 1
}

$fsGamePath = Join-Path $effGameRoot "fsgame.ltx"
$fsVars = Parse-FsGameLtx -FsGamePath $fsGamePath -GameRootPath $effGameRoot

if (-not [string]::IsNullOrWhiteSpace($AppDataRoot)) {
    $effAppDataRoot = $AppDataRoot.TrimEnd('\', '/')
    $effLogsDir     = Join-Path $effAppDataRoot "logs"
} else {
    $effAppDataRoot = $fsVars['$app_data_root$'].TrimEnd('\', '/')
    $effLogsDir     = $fsVars['$logs$'].TrimEnd('\', '/')
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $docsDir = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($docsDir)) {
        $docsDir = $PSScriptRoot
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $docsDir ("GAMMA-Gamepad-report-{0}.zip" -f $stamp)
}

Write-Bi -Ru ("Папка игры     : {0}" -f $effGameRoot) -En ("Game root      : {0}" -f $effGameRoot) -Color Cyan
Write-Bi -Ru ("Папка appdata  : {0}" -f $effAppDataRoot) -En ("Appdata root   : {0}" -f $effAppDataRoot) -Color Cyan
Write-Bi -Ru ("Папка логов    : {0}" -f $effLogsDir) -En ("Logs directory : {0}" -f $effLogsDir) -Color Cyan
if ($effMo2Root) {
    Write-Bi -Ru ("Папка MO2      : {0}" -f $effMo2Root) -En ("MO2 root       : {0}" -f $effMo2Root) -Color Cyan
} else {
    Write-Bi -Ru "Папка MO2      : не найдена (будет собран отчёт без списка модов MO2)" -En "MO2 root       : not found (collecting without MO2 modlist)" -Color Yellow
}

# Detect embedded usernames in xray_<user>.log / .bkp / .mdmp before building sanitization tokens
$extraUsers = New-Object System.Collections.Generic.List[string]
foreach ($dirCand in @($effLogsDir, (Join-Path $effGameRoot "logs"))) {
    if (Test-Path -LiteralPath $dirCand) {
        Get-ChildItem -LiteralPath $dirCand -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^xray_([^_.]+)\.(?:log|bkp)$') {
                $extraUsers.Add($Matches[1])
            } elseif ($_.Name -match '^xray_([^_]+)_\d{2}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.mdmp$') {
                $extraUsers.Add($Matches[1])
            }
        }
    }
}
$tokens = Build-SensitiveTokens -ExtraUserNames @($extraUsers.ToArray())

$maxZipBytes = [int64]$MaxZipSizeMB * 1MB
$maxLogBytes = [int64]$MaxLogFileMB * 1MB

# ------------------------------------------------------------------------------
# 1. Collect engine binaries info (D64: primary DX11/AVX monolith + optional DX12)
# ------------------------------------------------------------------------------
$binDir = Join-Path $effGameRoot "bin"
$binariesInfo = New-Object System.Collections.Generic.List[object]
$sdl3Info = $null
if (Test-Path -LiteralPath $binDir) {
    Get-ChildItem -LiteralPath $binDir -Filter "Anomaly*.exe" -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        if ($_.Name -notmatch 'SafeStart|Launcher') {
            $binariesInfo.Add((Get-PeInfo -FilePath $_.FullName))
        }
    }
    $verDx11 = Join-Path $binDir "VerifiedDX11.exe"
    if (Test-Path -LiteralPath $verDx11) {
        $binariesInfo.Add((Get-PeInfo -FilePath $verDx11))
    }
    $sdlPath = Join-Path $binDir "SDL3.dll"
    if (Test-Path -LiteralPath $sdlPath) {
        $sItem = Get-Item -LiteralPath $sdlPath
        $sdl3Info = [ordered]@{
            present        = $true
            size_bytes     = $sItem.Length
            last_write_utc = $sItem.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            sha256         = (Get-FileHash -LiteralPath $sdlPath -Algorithm SHA256).Hash.ToUpperInvariant()
            file_version   = $sItem.VersionInfo.FileVersion
        }
    } else {
        $sdl3Info = [ordered]@{ present = $false }
    }
}

# ------------------------------------------------------------------------------
# 2. Collect MO2 profile, modlist, G.A.M.M.A. version, and mod script hashes
# ------------------------------------------------------------------------------
$mo2ProfileDir = ""
$effProfileName = $ProfileName
if ($mo2Meta) {
    if ([string]::IsNullOrWhiteSpace($effProfileName)) {
        $effProfileName = $mo2Meta.selected_profile
    }
    if (-not [string]::IsNullOrWhiteSpace($effProfileName) -and (Test-Path -LiteralPath $mo2Meta.profiles_directory)) {
        $candProf = Join-Path $mo2Meta.profiles_directory $effProfileName
        if (Test-Path -LiteralPath $candProf) { $mo2ProfileDir = $candProf }
    }
    if ([string]::IsNullOrWhiteSpace($mo2ProfileDir) -and (Test-Path -LiteralPath $mo2Meta.profiles_directory)) {
        $firstProf = Get-ChildItem -LiteralPath $mo2Meta.profiles_directory -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($firstProf) {
            $mo2ProfileDir = $firstProf.FullName
            $effProfileName = $firstProf.Name
        }
    }
}

$installedModRoot = ""
if ($mo2Meta -and (Test-Path -LiteralPath $mo2Meta.mods_directory)) {
    $candMod = Join-Path $mo2Meta.mods_directory $ModName
    if (Test-Path -LiteralPath (Join-Path $candMod "gamedata")) {
        $installedModRoot = $candMod
    } else {
        # Fallback: locate any MO2 mod folder containing gp_bridge.script
        $foundMod = Get-ChildItem -LiteralPath $mo2Meta.mods_directory -Directory -ErrorAction SilentlyContinue | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "gamedata\scripts\gp_bridge.script")
        } | Select-Object -First 1
        if ($foundMod) { $installedModRoot = $foundMod.FullName }
    }
}
$gameScriptsDir = Join-Path $effGameRoot "gamedata\scripts"
$modScriptsDir  = if ($installedModRoot) { Join-Path $installedModRoot "gamedata\scripts" } else { "" }

$modMetaInfo = [ordered]@{
    mod_folder_detected = $(if ($installedModRoot) { Protect-PersonalData $installedModRoot $tokens } else { "" })
    meta_ini            = ""
    manifest_version    = ""
    gamma_def_version   = ""
    gamma_launcher_ver  = ""
    scripts             = @()
}

if ($installedModRoot -and (Test-Path -LiteralPath (Join-Path $installedModRoot "meta.ini"))) {
    $modMetaInfo.meta_ini = Protect-PersonalData (Read-TextSmart (Join-Path $installedModRoot "meta.ini")) $tokens
}
foreach ($manCand in @(
    $(if ($installedModRoot) { Join-Path $installedModRoot "manifest.sha256.json" } else { "" }),
    (Join-Path $effGameRoot "manifest.sha256.json")
)) {
    if (-not [string]::IsNullOrWhiteSpace($manCand) -and (Test-Path -LiteralPath $manCand)) {
        try {
            $mObj = (Read-TextSmart $manCand) | ConvertFrom-Json
            if ($mObj -and $mObj.PSObject.Properties['version']) {
                $modMetaInfo.manifest_version = [string]$mObj.version
            }
        } catch { }
        break
    }
}
if ($effMo2Root) {
    foreach ($gvCand in @(
        (Join-Path $effMo2Root ".Grok's Modpack Installer\G.A.M.M.A_definition_version.txt"),
        (Join-Path (Split-Path -Parent $effMo2Root) "Tools\GAMMA Launcher\version.txt")
    )) {
        if (Test-Path -LiteralPath $gvCand) {
            $modMetaInfo.gamma_def_version = (Read-TextSmart $gvCand).Trim()
            break
        }
    }
}

$scriptHashes = New-Object System.Collections.Generic.List[object]
foreach ($sSource in @(
    @{ Label = "game_gamedata"; Dir = $gameScriptsDir },
    @{ Label = "mo2_mod"; Dir = $modScriptsDir }
)) {
    if (-not [string]::IsNullOrWhiteSpace($sSource.Dir) -and (Test-Path -LiteralPath $sSource.Dir)) {
        Get-ChildItem -LiteralPath $sSource.Dir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^(?:gp_|ui_gp_).*\.script$'
        } | Sort-Object Name | ForEach-Object {
            $scriptHashes.Add([ordered]@{
                source = $sSource.Label
                name   = $_.Name
                bytes  = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            })
        }
    }
}
$modMetaInfo['scripts'] = @($scriptHashes.ToArray())

$mo2Summary = [ordered]@{
    profile_name             = $effProfileName
    total_entries            = 0
    enabled_mods             = 0
    disabled_mods            = 0
    gamepad_mod_line         = ""
    haru_qaw_enabled         = $false
    gamma_qaw_balance_enabled = $false
}
$modlistPath = if ($mo2ProfileDir) { Join-Path $mo2ProfileDir "modlist.txt" } else { "" }
if (-not [string]::IsNullOrWhiteSpace($modlistPath) -and (Test-Path -LiteralPath $modlistPath)) {
    $mlLines = [System.IO.File]::ReadAllLines($modlistPath, $Utf8NoBom)
    foreach ($line in $mlLines) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $mo2Summary.total_entries++
        if ($line.StartsWith("+")) { $mo2Summary.enabled_mods++ }
        elseif ($line.StartsWith("-")) { $mo2Summary.disabled_mods++ }

        if ($line -match '(?i)GAMMA Gamepad|Gamepad & Tactical UI') {
            $mo2Summary.gamepad_mod_line = $line.Trim()
        }
        if ($line -match '^\+.*Quick Action Wheel\s*-\s*HarukaSai') {
            $mo2Summary.haru_qaw_enabled = $true
        }
        if ($line -match '^\+.*G\.A\.M\.M\.A\.\s*Quick Action Wheel Balance') {
            $mo2Summary.gamma_qaw_balance_enabled = $true
        }
    }
}

# ------------------------------------------------------------------------------
# 3. Collect OS, hardware, and connected gamepads (without serial numbers)
# ------------------------------------------------------------------------------
$osInfo = $null; $cpuInfo = $null; $gpuList = @(); $pnpPads = @()
try { $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue } catch { }
try { $cpuInfo = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { }
try { $gpuList = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue) } catch { }
try {
    $pnpPads = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        $_.Present -eq $true -and (
            $_.Name -match '(?i)Controller|Gamepad|Joystick|Xbox|DualSense|DualShock|vJoy|HID-compliant game controller|Игровой контроллер' -or
            $_.DeviceID -match '(?i)IG_|VID_045E|VID_054C|VID_057E|VID_28DE'
        )
    } | ForEach-Object {
        # Strip unique instance serial suffix after last backslash for privacy
        $devIdSafe = ($_.DeviceID -replace '\\[^\\]+$', '\<INSTANCE>')
        [ordered]@{
            name      = Protect-PersonalData ([string]$_.Name) $tokens
            pnp_class = [string]$_.PNPClass
            status    = [string]$_.Status
            device_id = Protect-PersonalData $devIdSafe $tokens
        }
    })
} catch { }

$sysReportLines = New-Object System.Collections.Generic.List[string]
$sysReportLines.Add("================================================================================")
$sysReportLines.Add("GAMMA Gamepad & Tactical UI — System & Installation Summary")
$sysReportLines.Add("Collected (UTC): " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
$sysReportLines.Add("================================================================================")
$sysReportLines.Add("Game Root     : " + (Protect-PersonalData $effGameRoot $tokens))
$sysReportLines.Add("AppData Root  : " + (Protect-PersonalData $effAppDataRoot $tokens))
$sysReportLines.Add("Logs Dir      : " + (Protect-PersonalData $effLogsDir $tokens))
$sysReportLines.Add("MO2 Root      : " + $(if ($effMo2Root) { Protect-PersonalData $effMo2Root $tokens } else { "(not found)" }))
$sysReportLines.Add("MO2 Profile   : " + $(if ($effProfileName) { $effProfileName } else { "(none)" }))
$sysReportLines.Add("GAMMA Def Ver : " + $(if ($modMetaInfo.gamma_def_version) { $modMetaInfo.gamma_def_version } else { "(unknown)" }))
$sysReportLines.Add("Mod Version   : " + $(if ($modMetaInfo.manifest_version) { $modMetaInfo.manifest_version } else { "(manifest not found)" }))
$sysReportLines.Add("")
$sysReportLines.Add("--- Operating System & Hardware ---")
if ($osInfo) {
    $ramGb = [Math]::Round(($osInfo.TotalVisibleMemorySize / 1MB), 2)
    $sysReportLines.Add(("OS   : {0} (Build {1}, {2})" -f $osInfo.Caption, $osInfo.BuildNumber, $osInfo.OSArchitecture))
    $sysReportLines.Add(("RAM  : {0} GB" -f $ramGb))
}
if ($cpuInfo) {
    $sysReportLines.Add(("CPU  : {0} ({1} cores / {2} logical)" -f $cpuInfo.Name.Trim(), $cpuInfo.NumberOfCores, $cpuInfo.NumberOfLogicalProcessors))
}
    foreach ($g in $gpuList) {
        $vramMb = if ($g.PSObject.Properties['AdapterRAM'] -and $g.AdapterRAM) { [Math]::Round(($g.AdapterRAM / 1MB), 0) } else { 0 }
        $gName = if ($g.PSObject.Properties['Name']) { [string]$g.Name } else { "GPU" }
        $gDrv  = if ($g.PSObject.Properties['DriverVersion']) { [string]$g.DriverVersion } else { "?" }
        $gW    = if ($g.PSObject.Properties['CurrentHorizontalResolution']) { $g.CurrentHorizontalResolution } else { "?" }
        $gH    = if ($g.PSObject.Properties['CurrentVerticalResolution']) { $g.CurrentVerticalResolution } else { "?" }
        $sysReportLines.Add(("GPU  : {0} | Driver={1} | Mode={2}x{3} | VRAM~{4}MB" -f $gName, $gDrv, $gW, $gH, $vramMb))
    }
$sysReportLines.Add("")
$sysReportLines.Add("--- Connected Gamepad / Controller Devices (PnP) ---")
if ($pnpPads.Count -eq 0) {
    $sysReportLines.Add("(No active PnP gamepad controllers detected at collection time)")
} else {
    foreach ($p in $pnpPads) {
        $sysReportLines.Add(("- {0} [Class={1}, Status={2}, ID={3}]" -f $p.name, $p.pnp_class, $p.status, $p.device_id))
    }
}
$sysReportLines.Add("")
$sysReportLines.Add("--- Engine Binaries (D64: Primary G.A.M.M.A. DX11/AVX vs Optional DX12) ---")
if ($sdl3Info -and $sdl3Info.present) {
    $sysReportLines.Add(("SDL3.dll : PRESENT ({0} bytes, ver={1}, SHA256={2})" -f $sdl3Info.size_bytes, $sdl3Info.file_version, $sdl3Info.sha256))
} else {
    $sysReportLines.Add("SDL3.dll : MISSING from bin\")
}
foreach ($b in $binariesInfo) {
    $sysReportLines.Add(("- {0}: size={1}, pe_utc={2}, SDL3={3}, DX12={4}, SHA256={5} -> {6}" -f $b.name, $b.size_bytes, $b.pe_timestamp_utc, $b.imports_sdl3, $b.imports_dx12, $b.sha256.Substring(0, 16), $b.classification))
}
$sysReportLines.Add("")
$sysReportLines.Add("--- MO2 Modlist Summary ---")
$sysReportLines.Add(("Entries={0}, Enabled={1}, Disabled={2}" -f $mo2Summary.total_entries, $mo2Summary.enabled_mods, $mo2Summary.disabled_mods))
$sysReportLines.Add(("Gamepad Mod Entry        : {0}" -f $(if ($mo2Summary.gamepad_mod_line) { $mo2Summary.gamepad_mod_line } else { "(not found in modlist.txt)" })))
$sysReportLines.Add(("446 Haru QAW Enabled     : {0}" -f $mo2Summary.haru_qaw_enabled))
$sysReportLines.Add(("GAMMA QAW Balance Enabled: {0}" -f $mo2Summary.gamma_qaw_balance_enabled))

# ------------------------------------------------------------------------------
# 4. Discover logs, dumps, gamepad configs, and user settings
# ------------------------------------------------------------------------------
$collectedFiles = New-Object System.Collections.Generic.List[object]
$skippedFiles   = New-Object System.Collections.Generic.List[object]
$addedZipPaths  = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

$outDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$zipFs = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$archive = New-Object System.IO.Compression.ZipArchive($zipFs, [System.IO.Compression.ZipArchiveMode]::Update, $true)

try {
    function Try-AddTextFile {
        param(
            [string]$SourcePath,
            [string]$ZipEntryPath,
            [int64]$PerFileLimitBytes = $maxLogBytes
        )
        if (-not (Test-Path -LiteralPath $SourcePath)) { return }
        $safeEntry = Protect-FileName $ZipEntryPath $tokens
        if ($addedZipPaths.Contains($safeEntry)) { return }

        $rawText = Read-TextSmart -FilePath $SourcePath
        $sanitized = Protect-PersonalData -Text $rawText -Tokens $tokens
        $truncRes = Truncate-LogTextIfNeeded -Text $sanitized -MaxBytes $PerFileLimitBytes

        Add-ZipTextEntry -Archive $archive -EntryName $safeEntry -Content $truncRes.Text
        [void]$addedZipPaths.Add($safeEntry)
        $collectedFiles.Add([ordered]@{
            zip_path       = $safeEntry
            source_hint    = Protect-PersonalData $SourcePath $tokens
            original_bytes = (Get-Item -LiteralPath $SourcePath).Length
            truncated      = $truncRes.Truncated
            kind           = "text"
        })
    }

    # 4a. Engine logs: xray_*.log & xray_*.bkp in $logs$ and fallback game\logs\
    foreach ($logDirCand in @($effLogsDir, (Join-Path $effGameRoot "logs"))) {
        if (Test-Path -LiteralPath $logDirCand) {
            Get-ChildItem -LiteralPath $logDirCand -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '^xray_.*\.(?:log|bkp)$'
            } | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object {
                $targetName = "logs/" + (Protect-FileName $_.Name $tokens)
                Try-AddTextFile -SourcePath $_.FullName -ZipEntryPath $targetName -PerFileLimitBytes $maxLogBytes
            }
        }
    }

    # 4b. Gamepad error reports: actual code paths (gamepad_last_error.log) + legacy aliases
    $errCandidates = @(
        @{ Path = (Join-Path $effAppDataRoot "gamepad_last_error.log"); Zip = "errors/appdata_gamepad_last_error.log" },
        @{ Path = (Join-Path $effGameRoot "gamepad_last_error.log");    Zip = "errors/game_gamepad_last_error.log" },
        @{ Path = (Join-Path (Split-Path -Parent $effAppDataRoot) "gamepad_last_error.log"); Zip = "errors/root_gamepad_last_error.log" },
        @{ Path = (Join-Path $effLogsDir "gamepad_last_error.log");     Zip = "errors/logs_gamepad_last_error.log" },
        @{ Path = (Join-Path $effLogsDir "gamepad_errors.log");         Zip = "errors/logs_gamepad_errors.log" },
        @{ Path = (Join-Path $effAppDataRoot "gamepad_last_error.txt"); Zip = "errors/appdata_gamepad_last_error.txt" },
        @{ Path = (Join-Path $effLogsDir "gamepad_last_error.txt");     Zip = "errors/logs_gamepad_last_error.txt" }
    )
    foreach ($ec in $errCandidates) {
        if (Test-Path -LiteralPath $ec.Path) {
            Try-AddTextFile -SourcePath $ec.Path -ZipEntryPath $ec.Zip -PerFileLimitBytes $maxLogBytes
        }
    }

    # 4c. Gamepad profile, mappings, UI layout, user.ltx & axr_options.ltx
    $cfgCandidates = @(
        @{ Path = (Join-Path $effAppDataRoot "gamepad\profile.ltx");            Zip = "gamepad/profile.ltx" },
        @{ Path = (Join-Path $effAppDataRoot "gamepad\user_mappings.txt");      Zip = "gamepad/user_mappings.txt" },
        @{ Path = (Join-Path $effAppDataRoot "gamepad\ui-layout\user.ltx");     Zip = "gamepad/ui-layout_user.ltx" },
        @{ Path = (Join-Path $effAppDataRoot "gamepad\exports\bindings_export.ltx"); Zip = "gamepad/bindings_export.ltx" },
        @{ Path = $fsGamePath;                                                  Zip = "configs/fsgame.ltx" },
        @{ Path = (Join-Path $effGameRoot "commandline.txt");                   Zip = "configs/commandline.txt" },
        @{ Path = (Join-Path $effAppDataRoot "user.ltx");                       Zip = "configs/user.ltx" }
    )
    foreach ($cc in $cfgCandidates) {
        if (Test-Path -LiteralPath $cc.Path) {
            Try-AddTextFile -SourcePath $cc.Path -ZipEntryPath $cc.Zip -PerFileLimitBytes (2 * 1MB)
        }
    }

    $axrOptPath = Join-Path $effAppDataRoot "axr_options.ltx"
    if (Test-Path -LiteralPath $axrOptPath) {
        $axrRaw = Read-TextSmart -FilePath $axrOptPath
        $axrRelevant = @($axrRaw -split "\r?\n" | Where-Object {
            $_ -match '^\s*\[' -or $_ -match '(?i)gamepad|gp_|localization|gameplay|ui_'
        }) -join "`r`n"
        $axrSan = Protect-PersonalData -Text $axrRelevant -Tokens $tokens
        Add-ZipTextEntry -Archive $archive -EntryName "configs/axr_options_excerpt.ltx" -Content $axrSan
        $collectedFiles.Add([ordered]@{
            zip_path       = "configs/axr_options_excerpt.ltx"
            source_hint    = Protect-PersonalData $axrOptPath $tokens
            original_bytes = (Get-Item -LiteralPath $axrOptPath).Length
            truncated      = $true
            kind           = "text_excerpt"
        })
    }

    # 4d. MO2 profile files
    if ($mo2ProfileDir) {
        foreach ($mf in @("modlist.txt", "lockedorder.txt", "settings.ini", "initweaks.ini")) {
            $mp = Join-Path $mo2ProfileDir $mf
            if (Test-Path -LiteralPath $mp) {
                Try-AddTextFile -SourcePath $mp -ZipEntryPath ("mo2/" + $mf) -PerFileLimitBytes (2 * 1MB)
            }
        }
    }
    if ($installedModRoot -and (Test-Path -LiteralPath (Join-Path $installedModRoot "meta.ini"))) {
        Try-AddTextFile -SourcePath (Join-Path $installedModRoot "meta.ini") -ZipEntryPath "mod/meta.ini" -PerFileLimitBytes 262144
    }

    # 4e. Summary metadata files (written before optional dump/csv so budget calculation is exact)
    Add-ZipTextEntry -Archive $archive -EntryName "system_info.txt" -Content ($sysReportLines -join "`r`n")
    Add-ZipTextEntry -Archive $archive -EntryName "mod/scripts_hashes.json" -Content ($modMetaInfo | ConvertTo-Json -Depth 6)
    Add-ZipTextEntry -Archive $archive -EntryName "engine/binaries_info.json" -Content ([ordered]@{
        sdl3     = $sdl3Info
        binaries = @($binariesInfo.ToArray())
    } | ConvertTo-Json -Depth 6)

    # Flush current archive state to know exact compressed size so far
    $archive.Dispose()
    $zipFs.Flush()
    $curZipBytes = $zipFs.Length

    # Reopen archive for optional telemetry & minidumps within MaxZipSizeMB
    $archive = New-Object System.IO.Compression.ZipArchive($zipFs, [System.IO.Compression.ZipArchiveMode]::Update, $true)

    # Optional CSV telemetry (tail only, max 1 MB raw)
    foreach ($csvName in @("gamepad_telemetry.csv", "gp_perf_log.csv")) {
        $csvPath = Join-Path $effLogsDir $csvName
        if ((Test-Path -LiteralPath $csvPath) -and ($curZipBytes -lt ($maxZipBytes - 512KB))) {
            Try-AddTextFile -SourcePath $csvPath -ZipEntryPath ("logs/" + $csvName) -PerFileLimitBytes (1 * 1MB)
        }
    }

    # Optional Crash Minidumps (.mdmp) from $logs$, game\logs\, game\, or game\bin\
    $dumpSearchDirs = @($effLogsDir, (Join-Path $effGameRoot "logs"), $effGameRoot, $binDir) | Select-Object -Unique
    $allDumps = New-Object System.Collections.Generic.List[object]
    foreach ($dd in $dumpSearchDirs) {
        if (Test-Path -LiteralPath $dd) {
            Get-ChildItem -LiteralPath $dd -Filter "*.mdmp" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $allDumps.Add($_)
            }
        }
    }
    $sortedDumps = @($allDumps | Sort-Object LastWriteTimeUtc -Descending)
    $dumpMetadataList = New-Object System.Collections.Generic.List[object]
    foreach ($d in $sortedDumps) {
        $dumpMetadataList.Add([ordered]@{
            sanitized_name = Protect-FileName $d.Name $tokens
            size_bytes     = $d.Length
            last_write_utc = $d.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        })
    }

    if ($IncludeMinidump -and $sortedDumps.Count -gt 0) {
        $newestDump = $sortedDumps[0]
        $remainingBudget = $maxZipBytes - $zipFs.Length - 262144
        # Heuristic: minidumps typically compress 2x-4x; reject immediately if raw size > 4x remaining budget
        if ($remainingBudget -gt 65536 -and $newestDump.Length -le ($remainingBudget * 4)) {
            $dumpEntryName = "dumps/" + (Protect-FileName $newestDump.Name $tokens)
            Add-ZipBinaryEntry -Archive $archive -EntryName $dumpEntryName -SourcePath $newestDump.FullName
            $archive.Dispose()
            $zipFs.Flush()
            if ($zipFs.Length -gt $maxZipBytes) {
                # Roll back entry if compressed size still exceeded budget
                $archive = New-Object System.IO.Compression.ZipArchive($zipFs, [System.IO.Compression.ZipArchiveMode]::Update, $true)
                $existingEntry = $archive.GetEntry($dumpEntryName)
                if ($existingEntry) { $existingEntry.Delete() }
                $skippedFiles.Add([ordered]@{
                    name   = Protect-FileName $newestDump.Name $tokens
                    bytes  = $newestDump.Length
                    reason = "Exceeded MaxZipSizeMB ($MaxZipSizeMB MB) after compression"
                })
            } else {
                $archive = New-Object System.IO.Compression.ZipArchive($zipFs, [System.IO.Compression.ZipArchiveMode]::Update, $true)
                $collectedFiles.Add([ordered]@{
                    zip_path       = $dumpEntryName
                    source_hint    = Protect-PersonalData $newestDump.FullName $tokens
                    original_bytes = $newestDump.Length
                    truncated      = $false
                    kind           = "minidump"
                })
            }
        } else {
            $skippedFiles.Add([ordered]@{
                name   = Protect-FileName $newestDump.Name $tokens
                bytes  = $newestDump.Length
                reason = "Too large for remaining ZIP budget ($MaxZipSizeMB MB limit)"
            })
        }
    }

    # Final manifest
    $manifest = [ordered]@{
        schema_version      = "crash1-v1"
        target_baseline     = "D64: Original G.A.M.M.A. (xray-monolith DX11/AVX) & Anomaly (Optional PBR/DX12)"
        collected_utc       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        sanitization_tokens = @{
            user_token_count     = $tokens.AllUsers.Count
            computer_token_count = $tokens.Computers.Count
            replaced_with        = "<USER> / <PC>"
        }
        paths = @{
            game_root     = Protect-PersonalData $effGameRoot $tokens
            app_data_root = Protect-PersonalData $effAppDataRoot $tokens
            logs_dir      = Protect-PersonalData $effLogsDir $tokens
            mo2_root      = $(if ($effMo2Root) { Protect-PersonalData $effMo2Root $tokens } else { "" })
        }
        mo2_summary    = $mo2Summary
        sdl3           = $sdl3Info
        engine_binaries = @($binariesInfo.ToArray())
        minidumps_found = @($dumpMetadataList.ToArray())
        collected_files = @($collectedFiles.ToArray())
        skipped_files   = @($skippedFiles.ToArray())
    }
    Add-ZipTextEntry -Archive $archive -EntryName "report_manifest.json" -Content ($manifest | ConvertTo-Json -Depth 8)
} finally {
    if ($archive) { $archive.Dispose() }
    if ($zipFs) { $zipFs.Dispose() }
}

# ------------------------------------------------------------------------------
# 5. Self-verify privacy inside generated ZIP (read-only verification)
# ------------------------------------------------------------------------------
$privacyLeaks = New-Object System.Collections.Generic.List[string]
$totalEntriesCount = 0
$verifyArchive = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
    $totalEntriesCount = $verifyArchive.Entries.Count
    foreach ($entry in $verifyArchive.Entries) {
        foreach ($u in $tokens.SafeWordUsers) {
            if ($entry.FullName -imatch "(?<![A-Za-z0-9_])$([regex]::Escape($u))(?![A-Za-z0-9_])") {
                $privacyLeaks.Add("EntryName:$($entry.FullName)")
            }
        }
        if ($entry.FullName -notmatch '\.mdmp$') {
            $sr = New-Object System.IO.StreamReader($entry.Open(), $Utf8NoBom)
            $content = $sr.ReadToEnd()
            $sr.Dispose()
            foreach ($u in $tokens.SafeWordUsers) {
                if ($content -imatch "(?<![A-Za-z0-9_])$([regex]::Escape($u))(?![A-Za-z0-9_])") {
                    $privacyLeaks.Add("Content:$($entry.FullName)")
                }
            }
        }
    }
} finally {
    $verifyArchive.Dispose()
}

$zipSizeMB = [Math]::Round(((Get-Item -LiteralPath $OutputPath).Length / 1MB), 2)
Write-Host ""
Write-Bi `
    -Ru ("Собрано файлов : {0} (размер архива: {1} МБ / лимит {2} МБ)" -f $totalEntriesCount, $zipSizeMB, $MaxZipSizeMB) `
    -En ("Files packed    : {0} (archive size: {1} MB / limit {2} MB)" -f $totalEntriesCount, $zipSizeMB, $MaxZipSizeMB) `
    -Color Green

if ($privacyLeaks.Count -eq 0) {
    Write-Bi `
        -Ru "Проверка личных данных: ОК (имя пользователя и пути заменены на <USER>)." `
        -En "Privacy check          : OK (username and profile paths replaced with <USER>)." `
        -Color Green
} else {
    Write-Bi `
        -Ru ("ПРЕДУПРЕЖДЕНИЕ по приватности: проверьте записи: {0}" -f ($privacyLeaks -join ", ")) `
        -En ("PRIVACY WARNING: please inspect entries: {0}" -f ($privacyLeaks -join ", ")) `
        -Color Yellow
}

Write-Host ""
Write-Bi `
    -Ru ("ГОТОВО! Отчёт сохранён в:`n  {0}" -f $OutputPath) `
    -En ("DONE! Report saved to:`n  {0}" -f $OutputPath) `
    -Color Cyan
Write-Bi `
    -Ru "Приложите этот ZIP-файл к вашему сообщению об ошибке." `
    -En "Please attach this ZIP file to your bug report." `
    -Color White

if (-not $NoPause) {
    Write-Host ""
    Read-Host "Нажмите Enter для закрытия / Press Enter to close" | Out-Null
}
