[CmdletBinding()]
param(
    [string]$RootDirectory,
    [string]$FixtureDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootDirectory)) {
    $RootDirectory = Split-Path -Parent $PSScriptRoot
}
$RootDirectory = [IO.Path]::GetFullPath($RootDirectory)
$patcherPath = Join-Path $RootDirectory 'scripts/Patch-ParanoiaResolution.ps1'
$buildPath = Join-Path $RootDirectory 'tools/Build-Release.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Get-LowerHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Hash {
    param([string]$Path, [string]$Expected)
    $actual = Get-LowerHash $Path
    if ($actual -ne $Expected) {
        throw "Hash mismatch for '$Path'. Expected $Expected, got $actual."
    }
}

function Test-PowerShellSyntax {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell parser errors in '$Path': $($errors.Message -join '; ')"
    }
}

foreach ($path in @($patcherPath, $buildPath, $PSCommandPath)) {
    Test-PowerShellSyntax $path
}

$forbidden = @(Get-ChildItem -LiteralPath $RootDirectory -Recurse -File | Where-Object {
    $_.FullName -notlike "$(Join-Path $RootDirectory 'dist')*" -and
    $_.Extension -match '^\.(dll|exe|pak|wad)$'
})
Assert-True ($forbidden.Count -eq 0) 'repository contains a forbidden game/engine binary'

$expectedWrapperCommand = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"'
foreach ($wrapper in @('Install-1440p.cmd', 'Install-4K.cmd', 'Restore.cmd')) {
    $wrapperText = [IO.File]::ReadAllText((Join-Path $RootDirectory $wrapper))
    Assert-True $wrapperText.Contains($expectedWrapperCommand) "$wrapper does not use the absolute system PowerShell path"
}

$patcherText = [IO.File]::ReadAllText($patcherPath)
foreach ($requiredValue in @(
    'dd4a247ebb84cfa5f97643b950701d553536bae00e2e323d7aec55fff8b6d837'
    '1509779fe2281ed6467d04e2df9d89462516dde775439c58309e95695196fea3'
    '2436267422c1324b4939870e8b42c13cadd3777e2215e0e6cb7e4a6dfc66f65c'
    '8beec0ebbbe65c570e746db0fd23b39673737628524da6c02229fcd399edeb99'
    "Offset = 0xBF500"
    "Offset = 0xBF5C0"
    "Offset = 0x1C0E4"
    "Offset = 0x1C1D4"
)) {
    Assert-True $patcherText.Contains($requiredValue) "patcher is missing expected value: $requiredValue"
}

Write-Host '[PASS] Static source and safety checks.' -ForegroundColor Green

if ([string]::IsNullOrWhiteSpace($FixtureDirectory)) {
    Write-Host 'Integration fixture not supplied; exact-DLL runtime tests skipped.'
    return
}

$FixtureDirectory = [IO.Path]::GetFullPath($FixtureDirectory)
$stockXashHash = 'dd4a247ebb84cfa5f97643b950701d553536bae00e2e323d7aec55fff8b6d837'
$stockMenuHash = '1509779fe2281ed6467d04e2df9d89462516dde775439c58309e95695196fea3'
$finalXashHash = '2436267422c1324b4939870e8b42c13cadd3777e2215e0e6cb7e4a6dfc66f65c'
$finalMenuHash = '8beec0ebbbe65c570e746db0fd23b39673737628524da6c02229fcd399edeb99'

function Find-StockFile {
    param([string[]]$Candidates, [string]$ExpectedHash, [string]$Name)
    foreach ($candidate in $Candidates) {
        if ([IO.File]::Exists($candidate) -and (Get-LowerHash $candidate) -eq $ExpectedHash) {
            return $candidate
        }
    }
    throw "Could not find a pristine $Name fixture with SHA-256 $ExpectedHash."
}

$stockXashPath = Find-StockFile @(
    (Join-Path $FixtureDirectory 'xash.dll.original-build2664')
    (Join-Path $FixtureDirectory '.paranoia-resolution-patch-backup/xash.dll.original')
    (Join-Path $FixtureDirectory 'xash.dll')
) $stockXashHash 'xash.dll'
$stockMenuPath = Find-StockFile @(
    (Join-Path $FixtureDirectory 'menu.dll.original-build2664')
    (Join-Path $FixtureDirectory '.paranoia-resolution-patch-backup/menu.dll.original')
    (Join-Path $FixtureDirectory 'menu.dll')
) $stockMenuHash 'menu.dll'

$hostExecutable = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "ParanoiaPatchQA-$([Guid]::NewGuid().ToString('N'))"
$originalConfigText = "// сохраняем эту строку`r`nsetr vid_mode `"20`"`r`nsetr fullscreen `"0`"`r`nsetr vid_displayfrequency `"100`"`r`ncustom_value `"unchanged`"`r`n"
$configEncoding = [Text.Encoding]::GetEncoding(1251)
[byte[]]$originalConfigBytes = $configEncoding.GetBytes($originalConfigText)

function New-TestGame {
    param([string]$Name, [bool]$ReadOnlyFiles = $false)
    $game = Join-Path $testRoot $Name
    [void][IO.Directory]::CreateDirectory((Join-Path $game 'paranoia'))
    [IO.File]::Copy($stockXashPath, (Join-Path $game 'xash.dll'))
    [IO.File]::Copy($stockMenuPath, (Join-Path $game 'menu.dll'))
    [IO.File]::WriteAllBytes((Join-Path $game 'paranoia.exe'), (New-Object byte[] 0))
    [IO.File]::WriteAllBytes((Join-Path $game 'paranoia/video.cfg'), $originalConfigBytes)
    if ($ReadOnlyFiles) {
        (Get-Item -LiteralPath (Join-Path $game 'xash.dll')).IsReadOnly = $true
        (Get-Item -LiteralPath (Join-Path $game 'menu.dll')).IsReadOnly = $true
        (Get-Item -LiteralPath (Join-Path $game 'paranoia/video.cfg')).IsReadOnly = $true
    }
    return $game
}

function Invoke-PatcherChild {
    param([string]$Game, [string]$Action, [string]$Resolution = '1440p', [int]$ExpectedExitCode = 0)
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $patcherPath,
        '-Action', $Action,
        '-Resolution', $Resolution,
        '-GameDirectory', $Game
    )
    $output = & $hostExecutable @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $ExpectedExitCode) {
        throw "Patcher exit code was $exitCode, expected $ExpectedExitCode.`n$($output -join [Environment]::NewLine)"
    }
    return ,$output
}

function Assert-NoTransactionDebris {
    param([string]$Game)
    $debris = @(Get-ChildItem -LiteralPath $Game -Recurse -File | Where-Object { $_.Name -match '\.(tmp|rollback)$' })
    Assert-True ($debris.Count -eq 0) "transaction debris remains in $Game"
}

try {
    [void][IO.Directory]::CreateDirectory($testRoot)

    $normalGame = New-TestGame 'normal'
    [void](Invoke-PatcherChild $normalGame 'Install' '1440p')
    Assert-Hash (Join-Path $normalGame 'xash.dll') $finalXashHash
    Assert-Hash (Join-Path $normalGame 'menu.dll') $finalMenuHash
    $config1440 = $configEncoding.GetString([IO.File]::ReadAllBytes((Join-Path $normalGame 'paranoia/video.cfg')))
    Assert-True $config1440.Contains('setr vid_mode "22"') '1440p mode was not selected'
    Assert-True $config1440.Contains('custom_value "unchanged"') 'unrelated video.cfg line was changed'
    Assert-True (-not ($config1440 -replace "`r`n", '').Contains("`n")) 'CRLF line endings were not preserved'
    Assert-Hash (Join-Path $normalGame '.paranoia-resolution-patch-backup/xash.dll.original') $stockXashHash
    Assert-Hash (Join-Path $normalGame '.paranoia-resolution-patch-backup/menu.dll.original') $stockMenuHash

    [void](Invoke-PatcherChild $normalGame 'Install' '1440p')
    [void](Invoke-PatcherChild $normalGame 'Install' '4K')
    $config4K = $configEncoding.GetString([IO.File]::ReadAllBytes((Join-Path $normalGame 'paranoia/video.cfg')))
    Assert-True $config4K.Contains('setr vid_mode "10"') '4K mode was not selected'

    [void](Invoke-PatcherChild $normalGame 'Restore')
    Assert-Hash (Join-Path $normalGame 'xash.dll') $stockXashHash
    Assert-Hash (Join-Path $normalGame 'menu.dll') $stockMenuHash
    $restoredConfigBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $normalGame 'paranoia/video.cfg')))
    $originalConfigBase64 = [Convert]::ToBase64String($originalConfigBytes)
    Assert-True ($restoredConfigBase64 -eq $originalConfigBase64) 'video.cfg was not restored byte-for-byte'
    Assert-True (-not [IO.Directory]::Exists((Join-Path $normalGame '.paranoia-resolution-patch-backup'))) 'completed backup was not removed after restore'
    Assert-NoTransactionDebris $normalGame

    $unknownGame = New-TestGame 'unknown'
    [byte[]]$unknownBytes = [IO.File]::ReadAllBytes((Join-Path $unknownGame 'xash.dll'))
    $unknownBytes[100] = $unknownBytes[100] -bxor 0x01
    [IO.File]::WriteAllBytes((Join-Path $unknownGame 'xash.dll'), $unknownBytes)
    $unknownXashHash = Get-LowerHash (Join-Path $unknownGame 'xash.dll')
    $unknownMenuHash = Get-LowerHash (Join-Path $unknownGame 'menu.dll')
    $unknownConfigHash = Get-LowerHash (Join-Path $unknownGame 'paranoia/video.cfg')
    [void](Invoke-PatcherChild $unknownGame 'Install' '1440p' 1)
    Assert-True ((Get-LowerHash (Join-Path $unknownGame 'xash.dll')) -eq $unknownXashHash) 'unknown xash.dll was changed'
    Assert-True ((Get-LowerHash (Join-Path $unknownGame 'menu.dll')) -eq $unknownMenuHash) 'menu.dll changed after unknown-file rejection'
    Assert-True ((Get-LowerHash (Join-Path $unknownGame 'paranoia/video.cfg')) -eq $unknownConfigHash) 'video.cfg changed after unknown-file rejection'
    Assert-True (-not [IO.Directory]::Exists((Join-Path $unknownGame '.paranoia-resolution-patch-backup'))) 'backup was created for an unknown DLL'
    Assert-NoTransactionDebris $unknownGame

    $readOnlyGame = New-TestGame 'readonly' $true
    [void](Invoke-PatcherChild $readOnlyGame 'Install' '1440p')
    Assert-Hash (Join-Path $readOnlyGame 'xash.dll') $finalXashHash
    Assert-Hash (Join-Path $readOnlyGame 'menu.dll') $finalMenuHash
    Assert-True (Get-Item -LiteralPath (Join-Path $readOnlyGame 'xash.dll')).IsReadOnly 'xash.dll read-only attribute was not preserved'
    Assert-True (Get-Item -LiteralPath (Join-Path $readOnlyGame 'menu.dll')).IsReadOnly 'menu.dll read-only attribute was not preserved'
    Assert-True (-not (Get-Item -LiteralPath (Join-Path $readOnlyGame 'paranoia/video.cfg')).IsReadOnly) 'installed video.cfg should be writable'
    [void](Invoke-PatcherChild $readOnlyGame 'Restore')
    Assert-Hash (Join-Path $readOnlyGame 'xash.dll') $stockXashHash
    Assert-Hash (Join-Path $readOnlyGame 'menu.dll') $stockMenuHash
    Assert-True (Get-Item -LiteralPath (Join-Path $readOnlyGame 'paranoia/video.cfg')).IsReadOnly 'original video.cfg read-only attribute was not restored'
    Assert-NoTransactionDebris $readOnlyGame

    Write-Host '[PASS] Exact-DLL Windows PowerShell integration matrix.' -ForegroundColor Green
}
finally {
    if ([IO.Directory]::Exists($testRoot)) {
        Get-ChildItem -LiteralPath $testRoot -Recurse -Force | ForEach-Object {
            if (-not $_.PSIsContainer -and $_.IsReadOnly) { $_.IsReadOnly = $false }
        }
        [IO.Directory]::Delete($testRoot, $true)
    }
}
