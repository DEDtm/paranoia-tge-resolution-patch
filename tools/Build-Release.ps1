[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$Version = '1.0.0',

    [string]$SourceDirectory,

    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $SourceDirectory 'dist'
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$assetName = "paranoia-tge-resolution-patch-v$Version.zip"
$assetPath = Join-Path $OutputDirectory $assetName
$checksumPath = Join-Path $OutputDirectory 'SHA256SUMS.txt'
$allowList = @(
    'Install-1440p.cmd'
    'Install-4K.cmd'
    'Restore.cmd'
    'scripts/Patch-ParanoiaResolution.ps1'
    'README.md'
    'README.ru.md'
    'LICENSE'
    'NOTICE.md'
)

$patcherPath = Join-Path $SourceDirectory 'scripts/Patch-ParanoiaResolution.ps1'
$patcherText = [IO.File]::ReadAllText($patcherPath)
$versionPattern = "(?m)^\`$PatchVersion = '$([Regex]::Escape($Version))'(?:\r?\n|\z)"
if ($patcherText -notmatch $versionPattern) {
    throw "Patch script version does not match v$Version."
}

foreach ($relativePath in $allowList) {
    if (-not [IO.File]::Exists((Join-Path $SourceDirectory $relativePath))) {
        throw "Release input is missing: $relativePath"
    }
}

[void][IO.Directory]::CreateDirectory($OutputDirectory)
if ([IO.File]::Exists($assetPath)) { [IO.File]::Delete($assetPath) }
if ([IO.File]::Exists($checksumPath)) { [IO.File]::Delete($checksumPath) }

$stagingDirectory = Join-Path ([IO.Path]::GetTempPath()) "paranoia-patch-release-$([Guid]::NewGuid().ToString('N'))"
try {
    [void][IO.Directory]::CreateDirectory($stagingDirectory)
    foreach ($relativePath in $allowList) {
        $source = Join-Path $SourceDirectory $relativePath
        $destination = Join-Path $stagingDirectory $relativePath
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy($source, $destination, $false)
    }

    Compress-Archive -Path (Join-Path $stagingDirectory '*') -DestinationPath $assetPath -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($assetPath)
    try {
        $actualEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName.Replace('\', '/') } | Sort-Object)
    }
    finally {
        $archive.Dispose()
    }
    $expectedEntries = @($allowList | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
    if (@(Compare-Object $expectedEntries $actualEntries).Count -ne 0) {
        throw 'Release ZIP content differs from the explicit allowlist.'
    }

    $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($checksumPath, "$hash  $assetName`n", $utf8WithoutBom)
    Write-Host "Built: $assetPath"
    Write-Host "SHA-256: $hash"
}
finally {
    if ([IO.Directory]::Exists($stagingDirectory)) {
        [IO.Directory]::Delete($stagingDirectory, $true)
    }
}
