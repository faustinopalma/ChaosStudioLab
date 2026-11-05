$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Common helper parsing failed.' }
$definition = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Sync-LabTestTooling'
}, $true))[0]
. ([scriptblock]::Create($definition.Extent.Text))
$script:LabRoot = $root
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-tooling-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $fixture | Out-Null
$script:failChecksum = $false
$script:copiedArchive = $null
function Read-LabManifest { @{} }
function Get-LabSshOptions { @('-o', 'BatchMode=yes') }
function scp {
    $script:copiedArchive = $args[-2]
    $archive = [IO.Compression.ZipFile]::OpenRead($script:copiedArchive)
    try {
        if ($archive.Entries.Count -ne 9) { throw 'Private tooling package has missing or unexpected entries.' }
        $manifest = @($archive.Entries | Where-Object FullName -like '*.sha256')[0]
        $reader = [IO.StreamReader]::new($manifest.Open())
        try { $lines = $reader.ReadToEnd() -split "`n" } finally { $reader.Dispose() }
        if ($lines.Count -ne 8) { throw 'Each current source needs its own checksum.' }
        foreach ($line in $lines) {
            if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'Invalid private checksum manifest.' }
            $expected = $Matches[1]
            $entry = $archive.GetEntry($Matches[2])
            $stream = $entry.Open()
            try { $actual = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() }
            finally { $stream.Dispose() }
            if ($actual -cne $expected) { throw 'Packaged source and checksum differ.' }
        }
    } finally { $archive.Dispose() }
    $global:LASTEXITCODE = 0
}
function ssh {
    if ($args[-1] -notmatch 'sha256sum --quiet --check' -or $args[-1] -notmatch 'rm -- test-tools-') {
        throw 'Private checksum verification or exact temporary cleanup is missing.'
    }
    $global:LASTEXITCODE = if ($script:failChecksum) { 1 } else { 0 }
}
try {
    $result = Sync-LabTestTooling -ManifestPath (Join-Path $fixture 'manifest.json') -TunnelPort 50222
    if ($result.files.Count -ne 8 -or (Test-Path $script:copiedArchive)) { throw 'Tooling proof or exact local cleanup failed.' }
    $script:failChecksum = $true
    $rejected = $false
    try { Sync-LabTestTooling -ManifestPath (Join-Path $fixture 'manifest.json') -TunnelPort 50222 | Out-Null }
    catch { $rejected = $_.Exception.Message -like '*source checksum verification failed*' }
    if (-not $rejected -or (Test-Path $script:copiedArchive)) { throw 'A failed private checksum was accepted or its local package remained.' }
    'All eight current measurement tools are packaged consistently; private checksum failures remain explicit.'
} finally { Remove-Item -LiteralPath $fixture }
