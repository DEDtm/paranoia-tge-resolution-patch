[CmdletBinding()]
param(
    [ValidateSet('Install', 'Restore')]
    [string]$Action = 'Install',

    [ValidateSet('1440p', '4K')]
    [string]$Resolution = '1440p',

    [string]$GameDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PatchVersion = '1.0.0'
$StockXashHash = 'dd4a247ebb84cfa5f97643b950701d553536bae00e2e323d7aec55fff8b6d837'
$StockMenuHash = '1509779fe2281ed6467d04e2df9d89462516dde775439c58309e95695196fea3'
$FinalXashHash = '2436267422c1324b4939870e8b42c13cadd3777e2215e0e6cb7e4a6dfc66f65c'
$FinalMenuHash = '8beec0ebbbe65c570e746db0fd23b39673737628524da6c02229fcd399edeb99'

$KnownXashHashes = @{
    'dd4a247ebb84cfa5f97643b950701d553536bae00e2e323d7aec55fff8b6d837' = 'stock'
    '2f6226af7ccb02aad447688f8ee38b1577e4a057dc8a8f5cd99b8ad75b21977f' = '1440p-only'
    'a40806ce025b4346321bcebe434d3c9f04395d3d61583cd03d35ca19b10e2276' = '4K-only'
    '2436267422c1324b4939870e8b42c13cadd3777e2215e0e6cb7e4a6dfc66f65c' = '1440p+4K'
}

$KnownMenuHashes = @{
    '1509779fe2281ed6467d04e2df9d89462516dde775439c58309e95695196fea3' = 'stock'
    'bc23d20978a7b4de31b7623c997b8088b216ab0cf6a71fde356cd7bb04c8c5de' = '1440p-only'
    '3be5f853cd9b6343e264214f6b5b792aec684a2f6023f0ca81466eb0a3ac4933' = '4K-only'
    '8beec0ebbbe65c570e746db0fd23b39673737628524da6c02229fcd399edeb99' = '1440p+4K'
}

function Convert-HexToBytes {
    param([Parameter(Mandatory = $true)][string]$Hex)

    $clean = $Hex -replace '\s', ''
    if (($clean.Length % 2) -ne 0) {
        throw "Invalid hexadecimal byte string."
    }

    [byte[]]$bytes = New-Object byte[] ($clean.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($clean.Substring($index * 2, 2), 16)
    }
    return ,$bytes
}

$XashPatches = @(
    @{
        Name = '3840x2160 mode 10'
        Offset = 0xBF500
        Stock = Convert-HexToBytes 'D0 26 0C 10 20 03 00 00 E0 01 00 00 01 00 00 00'
        Patched = Convert-HexToBytes 'D0 26 0C 10 00 0F 00 00 70 08 00 00 01 00 00 00'
    },
    @{
        Name = '2560x1440 mode 22'
        Offset = 0xBF5C0
        Stock = Convert-HexToBytes '10 26 0C 10 00 0A 00 00 40 06 00 00 01 00 00 00'
        Patched = Convert-HexToBytes '10 26 0C 10 00 0A 00 00 A0 05 00 00 01 00 00 00'
    }
)

$MenuPatches = @(
    @{
        Name = '2560x1440 menu label'
        Offset = 0x1C0E4
        Stock = Convert-HexToBytes '32 35 36 30 20 78 20 31 36 30 30 20 28 77 69 64 65 29 00 00'
        Patched = Convert-HexToBytes '32 35 36 30 20 78 20 31 34 34 30 20 28 77 69 64 65 29 00 00'
    },
    @{
        Name = '3840x2160 menu label'
        Offset = 0x1C1D4
        Stock = Convert-HexToBytes '38 30 30 20 78 20 34 38 30 20 28 77 69 64 65 29 00 00 00 00'
        Patched = Convert-HexToBytes '33 38 34 30 20 78 20 32 31 36 30 20 28 77 69 64 65 29 00 00'
    }
)

function Get-BytesHash {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($Bytes)
        return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function Copy-ByteArray {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    [byte[]]$copy = New-Object byte[] $Bytes.Length
    [Array]::Copy($Bytes, $copy, $Bytes.Length)
    return ,$copy
}

function Test-BytesAtOffset {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Data,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][byte[]]$Pattern
    )

    if ($Offset -lt 0 -or ($Offset + $Pattern.Length) -gt $Data.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Pattern.Length; $index++) {
        if ($Data[$Offset + $index] -ne $Pattern[$index]) {
            return $false
        }
    }
    return $true
}

function Set-BytesAtOffset {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Data,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][byte[]]$Pattern
    )

    [Array]::Copy($Pattern, 0, $Data, $Offset, $Pattern.Length)
}

function Get-PatternCount {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Data,
        [Parameter(Mandatory = $true)][byte[]]$Pattern
    )

    $encoding = [Text.Encoding]::GetEncoding(28591)
    $dataText = $encoding.GetString($Data)
    $patternText = $encoding.GetString($Pattern)
    $count = 0
    $position = 0

    while ($position -le ($dataText.Length - $patternText.Length)) {
        $found = $dataText.IndexOf($patternText, $position, [StringComparison]::Ordinal)
        if ($found -lt 0) {
            break
        }
        $count++
        $position = $found + 1
    }
    return $count
}

function Convert-RecognizedBinary {
    param(
        [Parameter(Mandatory = $true)][byte[]]$CurrentBytes,
        [Parameter(Mandatory = $true)][hashtable]$KnownHashes,
        [Parameter(Mandatory = $true)][object[]]$Patches,
        [Parameter(Mandatory = $true)][string]$StockHash,
        [Parameter(Mandatory = $true)][string]$FinalHash,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $currentHash = Get-BytesHash $CurrentBytes
    if (-not $KnownHashes.ContainsKey($currentHash)) {
        throw "$FileName is not a recognized PARANOIA TGE build 2664 file. SHA-256: $currentHash"
    }

    [byte[]]$stockBytes = Copy-ByteArray $CurrentBytes
    foreach ($patch in $Patches) {
        $hasStock = Test-BytesAtOffset $stockBytes $patch.Offset $patch.Stock
        $hasPatched = Test-BytesAtOffset $stockBytes $patch.Offset $patch.Patched
        if ($hasStock -eq $hasPatched) {
            throw "$FileName has an unexpected byte pattern at offset 0x$('{0:X}' -f $patch.Offset) for $($patch.Name)."
        }

        $presentPattern = if ($hasStock) { $patch.Stock } else { $patch.Patched }
        if ((Get-PatternCount $stockBytes $presentPattern) -ne 1) {
            throw "$FileName does not contain one unique signature for $($patch.Name)."
        }

        if ($hasPatched) {
            Set-BytesAtOffset $stockBytes $patch.Offset $patch.Stock
        }
    }

    $reconstructedStockHash = Get-BytesHash $stockBytes
    if ($reconstructedStockHash -ne $StockHash) {
        throw "$FileName stock reconstruction failed. SHA-256: $reconstructedStockHash"
    }

    [byte[]]$finalBytes = Copy-ByteArray $stockBytes
    foreach ($patch in $Patches) {
        if ((Get-PatternCount $finalBytes $patch.Stock) -ne 1) {
            throw "$FileName stock signature is not unique before applying $($patch.Name)."
        }
        Set-BytesAtOffset $finalBytes $patch.Offset $patch.Patched
    }

    $builtFinalHash = Get-BytesHash $finalBytes
    if ($builtFinalHash -ne $FinalHash) {
        throw "$FileName patched output failed verification. SHA-256: $builtFinalHash"
    }

    return @{
        CurrentHash = $currentHash
        State = $KnownHashes[$currentHash]
        StockBytes = $stockBytes
        FinalBytes = $finalBytes
    }
}

function Assert-ExclusiveFileAccess {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    try {
        # Read access is intentional: it still detects an open game process via
        # FileShare.None, but it also works when a supported DLL is read-only.
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::None
        )
    }
    catch {
        throw "Cannot obtain exclusive write access to '$Path'. Close the game and check file permissions. $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Remove-FileIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([IO.File]::Exists($Path)) {
        [IO.File]::Delete($Path)
    }
}

function Commit-BinaryPair {
    param(
        [Parameter(Mandatory = $true)][string]$XashPath,
        [Parameter(Mandatory = $true)][byte[]]$XashBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedXashHash,
        [Parameter(Mandatory = $true)][string]$MenuPath,
        [Parameter(Mandatory = $true)][byte[]]$MenuBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedMenuHash,
        [Parameter(Mandatory = $true)][string]$OriginalXashHash,
        [Parameter(Mandatory = $true)][string]$OriginalMenuHash
    )

    Assert-ExclusiveFileAccess $XashPath
    Assert-ExclusiveFileAccess $MenuPath

    $token = [Guid]::NewGuid().ToString('N')
    $xashTemp = "$XashPath.$token.tmp"
    $menuTemp = "$MenuPath.$token.tmp"
    $xashRollback = "$XashPath.$token.rollback"
    $menuRollback = "$MenuPath.$token.rollback"
    $xashCommitted = $false
    $menuCommitted = $false
    $success = $false

    $xashAttributes = [IO.File]::GetAttributes($XashPath)
    $menuAttributes = [IO.File]::GetAttributes($MenuPath)
    $readOnlyFlag = [IO.FileAttributes]::ReadOnly

    try {
        if (($xashAttributes -band $readOnlyFlag) -ne 0) {
            [IO.File]::SetAttributes($XashPath, ($xashAttributes -band (-bnot $readOnlyFlag)))
        }
        if (($menuAttributes -band $readOnlyFlag) -ne 0) {
            [IO.File]::SetAttributes($MenuPath, ($menuAttributes -band (-bnot $readOnlyFlag)))
        }

        [IO.File]::WriteAllBytes($xashTemp, $XashBytes)
        [IO.File]::WriteAllBytes($menuTemp, $MenuBytes)
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($xashTemp))) -ne $ExpectedXashHash) {
            throw 'Staged xash.dll failed SHA-256 verification.'
        }
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($menuTemp))) -ne $ExpectedMenuHash) {
            throw 'Staged menu.dll failed SHA-256 verification.'
        }
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($XashPath))) -ne $OriginalXashHash) {
            throw 'xash.dll changed after validation. No files were replaced.'
        }
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($MenuPath))) -ne $OriginalMenuHash) {
            throw 'menu.dll changed after validation. No files were replaced.'
        }

        [IO.File]::Replace($xashTemp, $XashPath, $xashRollback, $true)
        $xashCommitted = $true
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($xashRollback))) -ne $OriginalXashHash) {
            throw 'xash.dll rollback copy failed SHA-256 verification.'
        }
        [IO.File]::Replace($menuTemp, $MenuPath, $menuRollback, $true)
        $menuCommitted = $true
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($menuRollback))) -ne $OriginalMenuHash) {
            throw 'menu.dll rollback copy failed SHA-256 verification.'
        }

        if ((Get-BytesHash ([IO.File]::ReadAllBytes($XashPath))) -ne $ExpectedXashHash) {
            throw 'Installed xash.dll failed SHA-256 verification.'
        }
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($MenuPath))) -ne $ExpectedMenuHash) {
            throw 'Installed menu.dll failed SHA-256 verification.'
        }
        $success = $true
    }
    catch {
        $commitError = $_
        if ($menuCommitted -and [IO.File]::Exists($menuRollback)) {
            [IO.File]::Copy($menuRollback, $MenuPath, $true)
        }
        if ($xashCommitted -and [IO.File]::Exists($xashRollback)) {
            [IO.File]::Copy($xashRollback, $XashPath, $true)
        }

        $restoredXashHash = Get-BytesHash ([IO.File]::ReadAllBytes($XashPath))
        $restoredMenuHash = Get-BytesHash ([IO.File]::ReadAllBytes($MenuPath))
        if ($restoredXashHash -ne $OriginalXashHash -or $restoredMenuHash -ne $OriginalMenuHash) {
            throw "Binary commit failed and rollback verification also failed. Preserve all *.rollback files. Original error: $($commitError.Exception.Message)"
        }
        throw $commitError
    }
    finally {
        $xashRollbackVerified = $success
        $menuRollbackVerified = $success
        if (-not $success) {
            try {
                $xashRollbackVerified = [IO.File]::Exists($XashPath) -and (Get-BytesHash ([IO.File]::ReadAllBytes($XashPath))) -eq $OriginalXashHash
            }
            catch { $xashRollbackVerified = $false }
            try {
                $menuRollbackVerified = [IO.File]::Exists($MenuPath) -and (Get-BytesHash ([IO.File]::ReadAllBytes($MenuPath))) -eq $OriginalMenuHash
            }
            catch { $menuRollbackVerified = $false }
        }

        try {
            if ([IO.File]::Exists($XashPath)) {
                [IO.File]::SetAttributes($XashPath, $xashAttributes)
            }
            if ([IO.File]::Exists($MenuPath)) {
                [IO.File]::SetAttributes($MenuPath, $menuAttributes)
            }
        }
        catch {
            Write-Warning "Could not restore a DLL file attribute: $($_.Exception.Message)"
        }

        Remove-FileIfPresent $xashTemp
        Remove-FileIfPresent $menuTemp
        if ($xashRollbackVerified) { Remove-FileIfPresent $xashRollback }
        if ($menuRollbackVerified) { Remove-FileIfPresent $menuRollback }
    }
}

function Get-VideoConfigBytes {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$OriginalBytes,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $encoding = [Text.Encoding]::GetEncoding(28591)
    $text = $encoding.GetString($OriginalBytes)
    $defaultNewLine = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } elseif ($text.Contains("`r")) { "`r" } else { "`r`n" }
    $values = @{
        'vid_displayfrequency' = '0'
        'fullscreen' = '1'
        'vid_mode' = $Mode
    }
    $seen = @{
        'vid_displayfrequency' = $false
        'fullscreen' = $false
        'vid_mode' = $false
    }

    $builder = New-Object Text.StringBuilder
    $linePattern = New-Object Text.RegularExpressions.Regex('\G([^\r\n]*)(\r\n|\n|\r|\z)')
    $cvarPattern = New-Object Text.RegularExpressions.Regex(
        '^[ \t]*(?:setr[ \t]+)?(?<name>vid_displayfrequency|fullscreen|vid_mode)[ \t]+.*$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $position = 0

    while ($position -lt $text.Length) {
        $match = $linePattern.Match($text, $position)
        if (-not $match.Success -or $match.Index -ne $position -or $match.Length -eq 0) {
            throw 'Unable to parse video.cfg without changing its encoding.'
        }

        $line = $match.Groups[1].Value
        $lineEnding = $match.Groups[2].Value
        $cvarMatch = $cvarPattern.Match($line)
        if ($cvarMatch.Success) {
            $name = $cvarMatch.Groups['name'].Value.ToLowerInvariant()
            if (-not $seen[$name]) {
                [void]$builder.Append("setr $name `"$($values[$name])`"")
                [void]$builder.Append($lineEnding)
                $seen[$name] = $true
            }
        }
        else {
            [void]$builder.Append($line)
            [void]$builder.Append($lineEnding)
        }
        $position += $match.Length
    }

    if ($text.Length -eq 0) {
        $builder = New-Object Text.StringBuilder
    }

    foreach ($name in @('vid_displayfrequency', 'fullscreen', 'vid_mode')) {
        if (-not $seen[$name]) {
            if ($builder.Length -gt 0) {
                $lastCharacter = $builder[$builder.Length - 1]
                if ($lastCharacter -ne "`n" -and $lastCharacter -ne "`r") {
                    [void]$builder.Append($defaultNewLine)
                }
            }
            [void]$builder.Append("setr $name `"$($values[$name])`"")
            [void]$builder.Append($defaultNewLine)
        }
    }

    return ,($encoding.GetBytes($builder.ToString()))
}

function Write-VideoConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [AllowNull()][Nullable[bool]]$ReadOnly = $null
    )

    $exists = [IO.File]::Exists($Path)
    $attributes = if ($exists) { [IO.File]::GetAttributes($Path) } else { [IO.FileAttributes]::Normal }
    $readOnlyFlag = [IO.FileAttributes]::ReadOnly
    $temp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $rollback = "$Path.$([Guid]::NewGuid().ToString('N')).rollback"
    $committed = $false
    $success = $false
    $originalHash = if ($exists) { Get-BytesHash ([IO.File]::ReadAllBytes($Path)) } else { $null }
    $expectedHash = Get-BytesHash $Bytes
    $desiredAttributes = $attributes
    if ($null -ne $ReadOnly) {
        if ([bool]$ReadOnly) {
            $desiredAttributes = $desiredAttributes -bor $readOnlyFlag
        }
        else {
            $desiredAttributes = $desiredAttributes -band (-bnot $readOnlyFlag)
        }
    }

    try {
        if ($exists -and (($attributes -band $readOnlyFlag) -ne 0)) {
            [IO.File]::SetAttributes($Path, ($attributes -band (-bnot $readOnlyFlag)))
        }
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if ($exists) {
            [IO.File]::Replace($temp, $Path, $rollback, $true)
        }
        else {
            [IO.File]::Move($temp, $Path)
        }
        $committed = $true

        if ((Get-BytesHash ([IO.File]::ReadAllBytes($Path))) -ne $expectedHash) {
            throw 'Installed video.cfg failed SHA-256 verification.'
        }
        [IO.File]::SetAttributes($Path, $desiredAttributes)
        $success = $true
    }
    catch {
        $writeError = $_
        if ($committed) {
            if ($exists -and [IO.File]::Exists($rollback)) {
                if ([IO.File]::Exists($Path)) {
                    [IO.File]::SetAttributes($Path, [IO.FileAttributes]::Normal)
                }
                [IO.File]::Copy($rollback, $Path, $true)
                [IO.File]::SetAttributes($Path, $attributes)
            }
            elseif (-not $exists -and [IO.File]::Exists($Path)) {
                [IO.File]::SetAttributes($Path, [IO.FileAttributes]::Normal)
                [IO.File]::Delete($Path)
            }
        }

        if ($exists) {
            if (-not [IO.File]::Exists($Path) -or (Get-BytesHash ([IO.File]::ReadAllBytes($Path))) -ne $originalHash) {
                throw "video.cfg update failed and rollback verification also failed. Preserve '$rollback'. Original error: $($writeError.Exception.Message)"
            }
        }
        elseif ([IO.File]::Exists($Path)) {
            throw "video.cfg update failed and rollback verification also failed. Preserve '$rollback'. Original error: $($writeError.Exception.Message)"
        }
        throw $writeError
    }
    finally {
        Remove-FileIfPresent $temp
        if ([IO.File]::Exists($Path)) {
            if ($success) {
                [IO.File]::SetAttributes($Path, $desiredAttributes)
            }
            else {
                [IO.File]::SetAttributes($Path, $attributes)
            }
        }
        if ($success -or ($exists -and [IO.File]::Exists($Path) -and (Get-BytesHash ([IO.File]::ReadAllBytes($Path))) -eq $originalHash) -or (-not $exists -and -not [IO.File]::Exists($Path))) {
            Remove-FileIfPresent $rollback
        }
    }
}

function Test-Backup {
    param([Parameter(Mandatory = $true)][string]$BackupDirectory)

    $manifestPath = Join-Path $BackupDirectory 'manifest.json'
    $xashBackupPath = Join-Path $BackupDirectory 'xash.dll.original'
    $menuBackupPath = Join-Path $BackupDirectory 'menu.dll.original'
    if (-not [IO.File]::Exists($manifestPath) -or -not [IO.File]::Exists($xashBackupPath) -or -not [IO.File]::Exists($menuBackupPath)) {
        throw "Backup directory is incomplete: $BackupDirectory"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([int]$manifest.schema_version -ne 1) {
        throw 'Unsupported backup manifest version.'
    }
    if ((Get-BytesHash ([IO.File]::ReadAllBytes($xashBackupPath))) -ne $StockXashHash) {
        throw 'Backup xash.dll.original failed SHA-256 verification.'
    }
    if ((Get-BytesHash ([IO.File]::ReadAllBytes($menuBackupPath))) -ne $StockMenuHash) {
        throw 'Backup menu.dll.original failed SHA-256 verification.'
    }
    if ([bool]$manifest.video_cfg_existed) {
        $videoBackupPath = Join-Path $BackupDirectory 'video.cfg.previous'
        if (-not [IO.File]::Exists($videoBackupPath)) {
            throw 'Backup manifest expects video.cfg.previous, but the file is missing.'
        }
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($videoBackupPath))) -ne [string]$manifest.video_cfg_sha256) {
            throw 'Backup video.cfg.previous failed SHA-256 verification.'
        }
    }
    return $manifest
}

function New-Backup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][byte[]]$StockXashBytes,
        [Parameter(Mandatory = $true)][byte[]]$StockMenuBytes,
        [Parameter(Mandatory = $true)][string]$SourceXashHash,
        [Parameter(Mandatory = $true)][string]$SourceMenuHash,
        [Parameter(Mandatory = $true)][string]$VideoConfigPath
    )

    if ([IO.Directory]::Exists($BackupDirectory)) {
        return (Test-Backup $BackupDirectory)
    }

    $temporaryDirectory = "$BackupDirectory.tmp-$([Guid]::NewGuid().ToString('N'))"
    $videoExists = [IO.File]::Exists($VideoConfigPath)
    $videoBytes = if ($videoExists) { [IO.File]::ReadAllBytes($VideoConfigPath) } else { $null }
    $videoReadOnly = if ($videoExists) { ([IO.File]::GetAttributes($VideoConfigPath) -band [IO.FileAttributes]::ReadOnly) -ne 0 } else { $false }

    try {
        [void][IO.Directory]::CreateDirectory($temporaryDirectory)
        [IO.File]::WriteAllBytes((Join-Path $temporaryDirectory 'xash.dll.original'), $StockXashBytes)
        [IO.File]::WriteAllBytes((Join-Path $temporaryDirectory 'menu.dll.original'), $StockMenuBytes)
        if ($videoExists) {
            [IO.File]::WriteAllBytes((Join-Path $temporaryDirectory 'video.cfg.previous'), $videoBytes)
        }

        $manifest = [ordered]@{
            schema_version = 1
            patch_version = $PatchVersion
            created_utc = [DateTime]::UtcNow.ToString('o')
            source_xash_sha256 = $SourceXashHash
            source_menu_sha256 = $SourceMenuHash
            stock_xash_sha256 = $StockXashHash
            stock_menu_sha256 = $StockMenuHash
            video_cfg_existed = $videoExists
            video_cfg_sha256 = if ($videoExists) { Get-BytesHash $videoBytes } else { $null }
            video_cfg_readonly = $videoReadOnly
        }
        $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText(
            (Join-Path $temporaryDirectory 'manifest.json'),
            ($manifest | ConvertTo-Json -Depth 4),
            $utf8WithoutBom
        )

        [void](Test-Backup $temporaryDirectory)
        [IO.Directory]::Move($temporaryDirectory, $BackupDirectory)
    }
    catch {
        if ([IO.Directory]::Exists($temporaryDirectory)) {
            [IO.Directory]::Delete($temporaryDirectory, $true)
        }
        throw
    }

    return (Test-Backup $BackupDirectory)
}

function Restore-VideoConfig {
    param(
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$VideoConfigPath
    )

    if ([bool]$Manifest.video_cfg_existed) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $BackupDirectory 'video.cfg.previous'))
        Write-VideoConfig $VideoConfigPath $bytes -ReadOnly ([bool]$Manifest.video_cfg_readonly)
    }
    elseif ([IO.File]::Exists($VideoConfigPath)) {
        $safeBytes = Get-VideoConfigBytes ([IO.File]::ReadAllBytes($VideoConfigPath)) '20'
        Write-VideoConfig $VideoConfigPath $safeBytes -ReadOnly $false
        Write-Warning 'video.cfg did not exist before installation. It was kept and reset to the original 1920x1080 mode instead of being deleted.'
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
        $GameDirectory = Split-Path -Parent $PSScriptRoot
    }
    $GameDirectory = [IO.Path]::GetFullPath($GameDirectory)
    $xashPath = Join-Path $GameDirectory 'xash.dll'
    $menuPath = Join-Path $GameDirectory 'menu.dll'
    $launcherPath = Join-Path $GameDirectory 'paranoia.exe'
    $videoConfigPath = Join-Path (Join-Path $GameDirectory 'paranoia') 'video.cfg'
    $backupDirectory = Join-Path $GameDirectory '.paranoia-resolution-patch-backup'

    foreach ($requiredPath in @($launcherPath, $xashPath, $menuPath)) {
        if (-not [IO.File]::Exists($requiredPath)) {
            throw "Required game file is missing: $requiredPath. Extract the patch into the folder containing paranoia.exe."
        }
    }
    if (-not [IO.Directory]::Exists((Split-Path -Parent $videoConfigPath))) {
        throw "The PARANOIA game data directory is missing: $(Split-Path -Parent $videoConfigPath)"
    }

    [byte[]]$currentXashBytes = [IO.File]::ReadAllBytes($xashPath)
    [byte[]]$currentMenuBytes = [IO.File]::ReadAllBytes($menuPath)
    if ($currentXashBytes.Length -ne 1030656) {
        throw "Unexpected xash.dll size: $($currentXashBytes.Length) bytes. Expected 1030656."
    }
    if ($currentMenuBytes.Length -ne 130048) {
        throw "Unexpected menu.dll size: $($currentMenuBytes.Length) bytes. Expected 130048."
    }

    $xashResult = Convert-RecognizedBinary $currentXashBytes $KnownXashHashes $XashPatches $StockXashHash $FinalXashHash 'xash.dll'
    $menuResult = Convert-RecognizedBinary $currentMenuBytes $KnownMenuHashes $MenuPatches $StockMenuHash $FinalMenuHash 'menu.dll'

    Write-Host "PARANOIA TGE Resolution Patch v$PatchVersion"
    Write-Host "Game directory: $GameDirectory"
    Write-Host "Detected xash.dll state: $($xashResult.State)"
    Write-Host "Detected menu.dll state: $($menuResult.State)"

    if ($Action -eq 'Install') {
        [void](New-Backup $backupDirectory $xashResult.StockBytes $menuResult.StockBytes $xashResult.CurrentHash $menuResult.CurrentHash $videoConfigPath)
        Write-Host "Verified stock backup: $backupDirectory"

        Commit-BinaryPair `
            $xashPath $xashResult.FinalBytes $FinalXashHash `
            $menuPath $menuResult.FinalBytes $FinalMenuHash `
            $xashResult.CurrentHash $menuResult.CurrentHash

        try {
            $mode = if ($Resolution -eq '4K') { '10' } else { '22' }
            [byte[]]$originalVideoBytes = if ([IO.File]::Exists($videoConfigPath)) { [IO.File]::ReadAllBytes($videoConfigPath) } else { New-Object byte[] 0 }
            [byte[]]$updatedVideoBytes = Get-VideoConfigBytes $originalVideoBytes $mode
            Write-VideoConfig $videoConfigPath $updatedVideoBytes -ReadOnly $false
        }
        catch {
            Commit-BinaryPair `
                $xashPath $currentXashBytes $xashResult.CurrentHash `
                $menuPath $currentMenuBytes $menuResult.CurrentHash `
                $FinalXashHash $FinalMenuHash
            throw "video.cfg update failed; DLL changes were rolled back. $($_.Exception.Message)"
        }

        Write-Host '[OK] Both 2560x1440 and 3840x2160 modes are installed.' -ForegroundColor Green
        if ($Resolution -eq '4K') {
            Write-Host '[OK] Selected 3840x2160 (mode 10), fullscreen, automatic refresh rate.' -ForegroundColor Green
        }
        else {
            Write-Host '[OK] Selected 2560x1440 (mode 22), fullscreen, automatic refresh rate.' -ForegroundColor Green
        }
        Write-Host 'Start paranoia.exe normally. Steam launch options are not required.'
    }
    else {
        if (-not [IO.Directory]::Exists($backupDirectory)) {
            throw "No patch backup exists at: $backupDirectory"
        }
        $manifest = Test-Backup $backupDirectory
        [byte[]]$stockXashBytes = [IO.File]::ReadAllBytes((Join-Path $backupDirectory 'xash.dll.original'))
        [byte[]]$stockMenuBytes = [IO.File]::ReadAllBytes((Join-Path $backupDirectory 'menu.dll.original'))

        Commit-BinaryPair `
            $xashPath $stockXashBytes $StockXashHash `
            $menuPath $stockMenuBytes $StockMenuHash `
            $xashResult.CurrentHash $menuResult.CurrentHash
        try {
            Restore-VideoConfig $backupDirectory $manifest $videoConfigPath
        }
        catch {
            Commit-BinaryPair `
                $xashPath $currentXashBytes $xashResult.CurrentHash `
                $menuPath $currentMenuBytes $menuResult.CurrentHash `
                $StockXashHash $StockMenuHash
            throw "video.cfg restore failed; DLL changes were rolled back. $($_.Exception.Message)"
        }

        Write-Host '[OK] Stock Xash3D build 2664 DLLs and the previous video configuration were restored.' -ForegroundColor Green
        try {
            [IO.Directory]::Delete($backupDirectory, $true)
            Write-Host '[OK] The completed patch backup was removed; a future installation will create a fresh backup.'
        }
        catch {
            Write-Warning "The game was restored, but the completed backup could not be removed. Delete it before a future installation: $backupDirectory"
        }
    }
    exit 0
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
