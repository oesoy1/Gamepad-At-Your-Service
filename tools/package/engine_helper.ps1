<#
.SYNOPSIS
    Gamepad At Your Service — Engine Binaries Installer & Rollback Helper.

.DESCRIPTION
    Installs or restores the gamepad-enabled X-Ray engine binaries and runtime DLLs
    in <Anomaly>\bin\ with automatic SHA-256 verified backup inside
    <Anomaly>\bin\_gamepad_backup\.

    Auto-detects <Anomaly> from ..\..\ModOrganizer.ini (gamePath=@ByteArray(...))
    when placed inside <GAMMA>\mods\<ModName>\, or prompts with a Windows folder
    picker if launched standalone.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Restore")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ru", "en")]
    [string]$Lang = "ru",

    [Parameter(Mandatory = $false)]
    [string]$AnomalyRoot = "",

    [Parameter(Mandatory = $false)]
    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$EngineFilesDir = $PSScriptRoot
$ModRoot = Split-Path -Parent $EngineFilesDir

function Get-Text {
    param([string]$Ru, [string]$En)
    if ($Lang -eq "en") { return $En }
    return $Ru
}

function Write-Info {
    param([string]$Text, [string]$Color = "Gray")
    Write-Host $Text -ForegroundColor $Color
}

function Test-PeImportsSdl3 {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $br = New-Object System.IO.BinaryReader($fs)
    try {
        if ($fs.Length -lt 128) { return $false }
        if ($br.ReadUInt16() -ne 0x5A4D) { return $false }
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        if ($peOffset -lt 0 -or ($peOffset + 24) -gt $fs.Length) { return $false }
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { return $false }

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
            return $false
        }

        $fs.Position = $importDirOffset
        $importRva = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        if ($importRva -eq 0) { return $false }

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
        if ($impOffset -lt 0) { return $false }

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
                if ($dll -ieq "SDL3.dll") { return $true }
            }
            $idx++
        }
        return $false
    } catch {
        return $false
    } finally {
        $br.Close()
        $fs.Close()
    }
}

function Normalize-AnomalyCandidate {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return "" }
    $p = $Candidate.Trim().Trim('"').Replace("/", "\")
    # Preserve UNC \\server\share prefix if present, collapse duplicate slashes elsewhere
    if ($p.StartsWith("\\")) {
        $p = "\\" + ($p.Substring(2) -replace "\\{2,}", "\")
    } else {
        $p = $p -replace "\\{2,}", "\"
    }
    $p = $p.TrimEnd("\")
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    if (Test-Path -LiteralPath (Join-Path $p "bin")) {
        return (Resolve-Path -LiteralPath $p).Path
    }
    # If the user selected <Anomaly>\bin directly, step one level up
    if ((Split-Path -Leaf $p) -ieq "bin") {
        $parent = Split-Path -Parent $p
        if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath (Join-Path $parent "bin"))) {
            $hasExe = @(Get-ChildItem -LiteralPath $p -Filter "AnomalyDX*.exe" -ErrorAction SilentlyContinue).Count -gt 0
            if ($hasExe -or (Test-Path -LiteralPath (Join-Path $parent "fsgame.ltx"))) {
                return (Resolve-Path -LiteralPath $parent).Path
            }
        }
    }
    return ""
}

function Get-AnomalyPathFromMo2Ini {
    param([string]$Mo2IniPath)
    if (-not (Test-Path -LiteralPath $Mo2IniPath)) { return "" }
    $lines = [System.IO.File]::ReadAllLines($Mo2IniPath, [System.Text.Encoding]::UTF8)
    foreach ($ln in $lines) {
        if ($ln -match "^\s*gamePath\s*=\s*(.+)$") {
            $rawVal = $Matches[1].Trim()
            if ($rawVal -match "^@ByteArray\((.*)\)$") {
                $rawVal = $Matches[1]
            }
            $rawVal = $rawVal.Replace("\\", "\").Replace("/", "\")
            $norm = Normalize-AnomalyCandidate -Candidate $rawVal
            if ($norm) { return $norm }
        }
    }
    return ""
}

function Select-AnomalyFolderDialog {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.StartPosition = "CenterScreen"
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.ShowInTaskbar = $false

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = Get-Text `
        -Ru "Выберите корневую папку S.T.A.L.K.E.R. Anomaly (внутри неё находится папка bin\):" `
        -En "Select your S.T.A.L.K.E.R. Anomaly root folder (the folder that contains bin\):"
    $dlg.ShowNewFolderButton = $false

    try {
        $res = $dlg.ShowDialog($owner)
        if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return "" }
        return $dlg.SelectedPath
    } finally {
        $dlg.Dispose()
        $owner.Dispose()
    }
}

function Resolve-AnomalyRootPath {
    if (-not [string]::IsNullOrWhiteSpace($AnomalyRoot)) {
        $norm = Normalize-AnomalyCandidate -Candidate $AnomalyRoot
        if (-not $norm) {
            throw (Get-Text `
                -Ru ("В указанной папке не найдена подпапка bin\: {0}" -f $AnomalyRoot) `
                -En ("Could not find a bin\ subfolder inside: {0}" -f $AnomalyRoot))
        }
        return [PSCustomObject]@{ Path = $norm; Source = "parameter" }
    }

    # Check two levels up from mod folder: <GAMMA>\mods\<ModName>\ -> <GAMMA>\ModOrganizer.ini
    $modsParent = Split-Path -Parent $ModRoot
    $mo2Dir = if ($modsParent) { Split-Path -Parent $modsParent } else { "" }
    if ($mo2Dir) {
        $mo2Ini = Join-Path $mo2Dir "ModOrganizer.ini"
        $fromIni = Get-AnomalyPathFromMo2Ini -Mo2IniPath $mo2Ini
        if ($fromIni) {
            return [PSCustomObject]@{ Path = $fromIni; Source = "mo2_ini" }
        }
    }

    # Check if mod files were unpacked straight into <Anomaly> root
    if ((Test-Path -LiteralPath (Join-Path $ModRoot "bin")) -and (Test-Path -LiteralPath (Join-Path $ModRoot "fsgame.ltx"))) {
        return [PSCustomObject]@{ Path = (Resolve-Path -LiteralPath $ModRoot).Path; Source = "standalone" }
    }

    if ($Silent) {
        throw (Get-Text `
            -Ru "Не удалось автоматически найти папку Anomaly (ModOrganizer.ini на два уровня выше не найден). Передайте -AnomalyRoot." `
            -En "Could not auto-detect Anomaly folder (ModOrganizer.ini not found two levels up). Pass -AnomalyRoot.")
    }

    Write-Info (Get-Text `
        -Ru "ModOrganizer.ini не найден рядом с папкой мода. Выберите корневую папку Anomaly в открывшемся окне..." `
        -En "ModOrganizer.ini was not found above the mod folder. Please choose your Anomaly root folder...") "Yellow"

    $picked = Select-AnomalyFolderDialog
    if ([string]::IsNullOrWhiteSpace($picked)) {
        Write-Info (Get-Text -Ru "Операция отменена пользователем." -En "Operation cancelled by user.") "Yellow"
        exit 1
    }

    $normPicked = Normalize-AnomalyCandidate -Candidate $picked
    if (-not $normPicked) {
        throw (Get-Text `
            -Ru ("В выбранной папке не найдена папка bin\: {0}`nНужна именно корневая папка Anomaly (рядом с папками bin, appdata, db)." -f $picked) `
            -En ("The selected folder does not contain bin\: {0}`nPlease select the root Anomaly folder (where bin, appdata, and db live)." -f $picked))
    }
    return [PSCustomObject]@{ Path = $normPicked; Source = "dialog" }
}

function Assert-GameNotRunning {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "^AnomalyDX" })
    if ($running.Count -gt 0) {
        $names = ($running | ForEach-Object { $_.ProcessName + ".exe" } | Select-Object -Unique) -join ", "
        Write-Host ""
        Write-Host (Get-Text `
            -Ru ("ОШИБКА: Игра сейчас запущена ({0})." -f $names) `
            -En ("ERROR: The game is currently running ({0})." -f $names)) -ForegroundColor Red
        Write-Host (Get-Text `
            -Ru "Пожалуйста, полностью закройте S.T.A.L.K.E.R. Anomaly / G.A.M.M.A. и запустите скрипт снова." `
            -En "Please close S.T.A.L.K.E.R. Anomaly / G.A.M.M.A. completely and run this helper again.") -ForegroundColor Yellow
        exit 1
    }
}

function Get-FileSha256Upper {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-EnginePayloadFiles {
    $resolvedRoot = (Resolve-Path -LiteralPath $EngineFilesDir).Path
    $list = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relWin = $_.FullName.Substring($resolvedRoot.Length + 1)
        if ($relWin -ieq "engine_helper.ps1") { return }
        $relSlash = $relWin -replace "\\", "/"
        $list.Add([PSCustomObject]@{
            RelWin     = $relWin
            RelPath    = $relSlash
            SourcePath = $_.FullName
            Sha256     = Get-FileSha256Upper -Path $_.FullName
            SizeBytes  = $_.Length
        })
    }
    return $list
}

function Remove-EmptySubdirsUpTo {
    param([string]$StartDir, [string]$StopDir)
    $stopNorm = (Resolve-Path -LiteralPath $StopDir).Path.TrimEnd("\")
    $cur = $StartDir
    while (-not [string]::IsNullOrWhiteSpace($cur)) {
        if (-not (Test-Path -LiteralPath $cur)) { break }
        $curNorm = (Resolve-Path -LiteralPath $cur).Path.TrimEnd("\")
        if ($curNorm -ieq $stopNorm) { break }
        if (-not $curNorm.StartsWith($stopNorm + "\", [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $items = @(Get-ChildItem -LiteralPath $curNorm -Force -ErrorAction SilentlyContinue)
        if ($items.Count -eq 0) {
            Remove-Item -LiteralPath $curNorm -Force
            $cur = Split-Path -Parent $curNorm
        } else {
            break
        }
    }
}

function Invoke-EngineInstall {
    param([string]$TargetAnomalyRoot)

    $binDir = Join-Path $TargetAnomalyRoot "bin"
    $backupDir = Join-Path $binDir "_gamepad_backup"
    $backupManifestPath = Join-Path $backupDir "backup_manifest.json"

    $payload = @(Get-EnginePayloadFiles)
    if ($payload.Count -eq 0) {
        throw (Get-Text `
            -Ru "В папке engine_files\ не найдено ни одного файла движка." `
            -En "No engine payload files were found inside engine_files\.")
    }

    # Read package metadata if available
    $modVersion = ""
    $modTarget = ""
    $pkgManifestPath = Join-Path $ModRoot "manifest.sha256.json"
    if (Test-Path -LiteralPath $pkgManifestPath) {
        try {
            $pm = ([System.IO.File]::ReadAllText($pkgManifestPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
            $modVersion = [string]$pm.version
            $modTarget = [string]$pm.target
        } catch {
            $modVersion = ""
        }
    }

    # Load previous backup manifest if one exists
    $existingEntries = @{}
    $existingOrder = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $backupManifestPath) {
        $prevJson = ([System.IO.File]::ReadAllText($backupManifestPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
        foreach ($item in @($prevJson.files)) {
            $key = ([string]$item.rel_path -replace "\\", "/").ToLowerInvariant()
            if (-not $existingEntries.ContainsKey($key)) {
                $existingOrder.Add($key)
            }
            $existingEntries[$key] = $item
        }
    }

    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $backedUpNew = 0
    $backupUpdated = 0
    $backupPreserved = 0
    $trackedNew = 0
    $installedFiles = 0

    $updatedEntries = @{}
    $updatedOrder = New-Object System.Collections.Generic.List[string]

    foreach ($pf in $payload) {
        $key = $pf.RelPath.ToLowerInvariant()
        $dstPath = Join-Path $binDir $pf.RelWin
        $bakPath = Join-Path $backupDir $pf.RelWin
        $dstParent = Split-Path -Parent $dstPath
        if (-not (Test-Path -LiteralPath $dstParent)) {
            New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
        }

        $prev = if ($existingEntries.ContainsKey($key)) { $existingEntries[$key] } else { $null }
        $existedBefore = $false
        $origHash = ""

        if (Test-Path -LiteralPath $dstPath) {
            $dstHash = Get-FileSha256Upper -Path $dstPath
            if ($null -ne $prev) {
                $prevOurHash = if ($prev.our_sha256) { ([string]$prev.our_sha256).ToUpperInvariant() } else { "" }
                $prevOrigHash = if ($prev.original_sha256) { ([string]$prev.original_sha256).ToUpperInvariant() } else { "" }
                $prevExisted = [bool]$prev.existed_before

                if ($dstHash -eq $pf.Sha256) {
                    # Current modded file is already in bin\; never overwrite saved backup
                    $existedBefore = $prevExisted
                    $origHash = $prevOrigHash
                    if ($existedBefore -and (Test-Path -LiteralPath $bakPath)) { $backupPreserved++ }
                } elseif ($prevOurHash -and ($dstHash -eq $prevOurHash)) {
                    # Earlier version of our mod is in bin\; preserve the original backup
                    $existedBefore = $prevExisted
                    $origHash = $prevOrigHash
                    if ($existedBefore -and (Test-Path -LiteralPath $bakPath)) { $backupPreserved++ }
                } elseif ($prevExisted -and $prevOrigHash -and ($dstHash -eq $prevOrigHash) -and (Test-Path -LiteralPath $bakPath)) {
                    # Exact original file is already saved in _gamepad_backup
                    $existedBefore = $true
                    $origHash = $prevOrigHash
                    $backupPreserved++
                } else {
                    # External change (for example, G.A.M.M.A. Launcher updated stock EXE)
                    $isModdedExe = ($pf.RelWin -match "(?i)\.exe$") -and (Test-PeImportsSdl3 -FilePath $dstPath)
                    if ($isModdedExe -and (Test-Path -LiteralPath $bakPath)) {
                        $existedBefore = $prevExisted
                        $origHash = $prevOrigHash
                        $backupPreserved++
                    } else {
                        $bakParent = Split-Path -Parent $bakPath
                        if (-not (Test-Path -LiteralPath $bakParent)) {
                            New-Item -ItemType Directory -Path $bakParent -Force | Out-Null
                        }
                        Copy-Item -LiteralPath $dstPath -Destination $bakPath -Force
                        $existedBefore = $true
                        $origHash = $dstHash
                        if ($prevExisted) { $backupUpdated++ } else { $backedUpNew++ }
                    }
                }
            } else {
                # First-time backup for this path
                $isModdedExe = ($pf.RelWin -match "(?i)\.exe$") -and (Test-PeImportsSdl3 -FilePath $dstPath)
                $legacyOrig = "$dstPath.orig"
                if ($isModdedExe -and (Test-Path -LiteralPath $legacyOrig) -and -not (Test-PeImportsSdl3 -FilePath $legacyOrig)) {
                    $bakParent = Split-Path -Parent $bakPath
                    if (-not (Test-Path -LiteralPath $bakParent)) {
                        New-Item -ItemType Directory -Path $bakParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $legacyOrig -Destination $bakPath -Force
                    $existedBefore = $true
                    $origHash = Get-FileSha256Upper -Path $bakPath
                    $backedUpNew++
                } else {
                    $bakParent = Split-Path -Parent $bakPath
                    if (-not (Test-Path -LiteralPath $bakParent)) {
                        New-Item -ItemType Directory -Path $bakParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $dstPath -Destination $bakPath -Force
                    $existedBefore = $true
                    $origHash = $dstHash
                    $backedUpNew++
                }
            }
        } else {
            if ($null -ne $prev) {
                $existedBefore = [bool]$prev.existed_before
                $origHash = if ($prev.original_sha256) { ([string]$prev.original_sha256).ToUpperInvariant() } else { "" }
                if ($existedBefore -and (Test-Path -LiteralPath $bakPath)) { $backupPreserved++ }
            } else {
                $existedBefore = $false
                $origHash = ""
                $trackedNew++
            }
        }

        Copy-Item -LiteralPath $pf.SourcePath -Destination $dstPath -Force
        $actualHash = Get-FileSha256Upper -Path $dstPath
        if ($actualHash -ne $pf.Sha256) {
            throw (Get-Text `
                -Ru ("Ошибка проверки контрольной суммы после копирования {0}." -f $pf.RelPath) `
                -En ("Checksum verification failed after copying {0}." -f $pf.RelPath))
        }
        $installedFiles++

        $updatedOrder.Add($key)
        $updatedEntries[$key] = [ordered]@{
            rel_path        = $pf.RelPath
            existed_before  = $existedBefore
            original_sha256 = $origHash
            our_sha256      = $pf.Sha256
        }
    }

    # Keep any older tracked entries from a previous edition so Restore stays complete
    foreach ($oldKey in $existingOrder) {
        if (-not $updatedEntries.ContainsKey($oldKey)) {
            $oldItem = $existingEntries[$oldKey]
            $updatedOrder.Add($oldKey)
            $updatedEntries[$oldKey] = [ordered]@{
                rel_path        = [string]$oldItem.rel_path
                existed_before  = [bool]$oldItem.existed_before
                original_sha256 = [string]$oldItem.original_sha256
                our_sha256      = [string]$oldItem.our_sha256
            }
        }
    }

    $manifestList = @($updatedOrder | ForEach-Object { $updatedEntries[$_] })
    $manifestObj = [ordered]@{
        schema_version = 1
        tool           = "engine_helper.ps1"
        updated_at     = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
        anomaly_root   = $TargetAnomalyRoot
        mod_version    = $modVersion
        target         = $modTarget
        files          = $manifestList
    }
    [System.IO.File]::WriteAllText($backupManifestPath, ($manifestObj | ConvertTo-Json -Depth 6), $Utf8NoBom)

    Write-Host ""
    Write-Info (Get-Text `
        -Ru ("Готово! Установлено файлов движка в {0}: {1}" -f $binDir, $installedFiles) `
        -En ("Done! Installed {1} engine file(s) into {0}" -f $binDir, $installedFiles)) "Green"
    Write-Info (Get-Text `
        -Ru ("Резервная копия (_gamepad_backup): новых оригиналов={0}, обновлено стоковых={1}, сохранено прежних={2}, новых добавлено={3}" -f $backedUpNew, $backupUpdated, $backupPreserved, $trackedNew) `
        -En ("Backup (_gamepad_backup): new originals={0}, updated stock={1}, preserved={2}, newly added={3}" -f $backedUpNew, $backupUpdated, $backupPreserved, $trackedNew)) "Gray"

    $hasDlssExe = @($payload | Where-Object { $_.RelPath -ieq "AnomalyDX12-DLSS.exe" }).Count -gt 0
    if ($hasDlssExe) {
        Write-Info (Get-Text `
            -Ru "Важно для версии DLSS: выберите AnomalyDX12-DLSS.exe как запускаемый файл в Mod Organizer 2." `
            -En "Important for DLSS edition: set AnomalyDX12-DLSS.exe as your launch executable in Mod Organizer 2.") "Cyan"
    }
    Write-Info (Get-Text `
        -Ru "Проверьте, что мод «GAMMA Gamepad & Tactical UI» включён в самом низу левого списка MO2." `
        -En "Make sure 'GAMMA Gamepad & Tactical UI' is enabled at the very bottom of your MO2 left pane.") "Cyan"
}

function Invoke-EngineRestore {
    param([string]$TargetAnomalyRoot)

    $binDir = Join-Path $TargetAnomalyRoot "bin"
    $backupDir = Join-Path $binDir "_gamepad_backup"
    $backupManifestPath = Join-Path $backupDir "backup_manifest.json"

    if (-not (Test-Path -LiteralPath $backupManifestPath)) {
        Write-Host ""
        Write-Info (Get-Text `
            -Ru ("Резервная копия в {0} не найдена — возвращать нечего (откат уже выполнен или движок не ставился)." -f $backupDir) `
            -En ("No backup found in {0} — nothing to restore (already restored or engine files were not installed)." -f $backupDir)) "Yellow"
        return
    }

    $manifest = ([System.IO.File]::ReadAllText($backupManifestPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
    $restoredCount = 0
    $removedAddedCount = 0
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($manifest.files)) {
        $relSlash = [string]$entry.rel_path
        $relWin = $relSlash -replace "/", "\"
        $binTarget = Join-Path $binDir $relWin
        $bakSource = Join-Path $backupDir $relWin

        if ([bool]$entry.existed_before) {
            if (-not (Test-Path -LiteralPath $bakSource)) {
                $errors.Add((Get-Text `
                    -Ru ("Не найден файл резервной копии: {0}" -f $bakSource) `
                    -En ("Missing backup file: {0}" -f $bakSource)))
                continue
            }
            $targetParent = Split-Path -Parent $binTarget
            if (-not (Test-Path -LiteralPath $targetParent)) {
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $bakSource -Destination $binTarget -Force
            $expectedHash = if ($entry.original_sha256) { ([string]$entry.original_sha256).ToUpperInvariant() } else { "" }
            $actualHash = Get-FileSha256Upper -Path $binTarget
            if ($expectedHash -and ($actualHash -ne $expectedHash)) {
                $errors.Add((Get-Text `
                    -Ru ("Контрольная сумма восстановленного файла не сошлась: {0}" -f $relSlash) `
                    -En ("Checksum mismatch after restoring: {0}" -f $relSlash)))
                continue
            }
            $restoredCount++
        } else {
            if (Test-Path -LiteralPath $binTarget) {
                Remove-Item -LiteralPath $binTarget -Force
                $removedAddedCount++
            }
            $targetParent = Split-Path -Parent $binTarget
            Remove-EmptySubdirsUpTo -StartDir $targetParent -StopDir $binDir
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host ""
        foreach ($err in $errors) {
            Write-Host ("[FAIL] {0}" -f $err) -ForegroundColor Red
        }
        throw (Get-Text `
            -Ru "Откат завершился с ошибками. Папка _gamepad_backup сохранена для безопасности." `
            -En "Rollback encountered errors. _gamepad_backup was kept intact for safety.")
    }

    Remove-Item -LiteralPath $backupDir -Recurse -Force

    Write-Host ""
    Write-Info (Get-Text `
        -Ru ("Готово! Оригинальные файлы в {0} восстановлены." -f $binDir) `
        -En ("Done! Original files in {0} have been restored." -f $binDir)) "Green"
    Write-Info (Get-Text `
        -Ru ("Восстановлено оригиналов: {0}, удалено добавленных файлов мода: {1}, папка _gamepad_backup очищена." -f $restoredCount, $removedAddedCount) `
        -En ("Restored originals: {0}, removed added mod files: {1}, _gamepad_backup cleaned up." -f $restoredCount, $removedAddedCount)) "Gray"
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Info (Get-Text `
    -Ru (" GAMEPAD AT YOUR SERVICE — {0}" -f $(if ($Action -eq "Install") { "УСТАНОВКА ФАЙЛОВ ДВИЖКА" } else { "ВОЗВРАТ ОРИГИНАЛЬНОГО ДВИЖКА" })) `
    -En (" GAMEPAD AT YOUR SERVICE — {0}" -f $(if ($Action -eq "Install") { "INSTALL ENGINE FILES" } else { "RESTORE ORIGINAL ENGINE" }))) "Cyan"
Write-Host "========================================================================" -ForegroundColor Cyan

Assert-GameNotRunning
$resolved = Resolve-AnomalyRootPath
Write-Info (Get-Text `
    -Ru ("Папка Anomaly : {0} (источник: {1})" -f $resolved.Path, $resolved.Source) `
    -En ("Anomaly root  : {0} (source: {1})" -f $resolved.Path, $resolved.Source)) "White"

if ($Action -eq "Install") {
    Invoke-EngineInstall -TargetAnomalyRoot $resolved.Path
} else {
    Invoke-EngineRestore -TargetAnomalyRoot $resolved.Path
}
exit 0
