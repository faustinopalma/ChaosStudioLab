$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Evidence operator does not parse.' }
$definition = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Save-LabRunnerEvidence'
}, $true)
if ($null -eq $definition) { throw 'Production evidence helper is missing.' }
. ([scriptblock]::Create($definition.Extent.Text))
$stateRoot = Join-Path ([IO.Path]::GetTempPath()) "csl-evidence-$([Guid]::NewGuid().ToString('N'))"
$source = Join-Path $stateRoot 'source'
$evidenceRoot = Join-Path $stateRoot 'evidence'
$run = Join-Path $source 'results\fixture'
$fixtureArchive = Join-Path $stateRoot 'fixture.tgz'
$Phase = 'baseline'; $TunnelPort = 50222; $sshArgs = @(); $sshOptions = @()
$ManifestPath = Join-Path $stateRoot 'manifest.json'
function Read-LabManifest([string] $Path) { @{} }
function Get-LabSshOptions([hashtable] $Manifest, [string] $StateRoot) { @() }
$fixture = @{packExit = 0; packMessage = ''; copyExit = 0; copies = 0}
function ssh {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    if ($Arguments[-1] -ne 'cd ~/csl && tar -czf baseline-evidence.tgz results') { throw 'Evidence packing contract changed.' }
    $global:LASTEXITCODE = $fixture.packExit
    if ($fixture.packMessage) { $fixture.packMessage }
}
function scp {
    param([Alias('P')][int] $Port, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    $fixture.copies++
    if ($fixture.copyExit -eq 0) { Copy-Item -LiteralPath $fixtureArchive -Destination $Arguments[-1] }
    $global:LASTEXITCODE = $fixture.copyExit
}
try {
    New-Item -ItemType Directory -Path $run, $evidenceRoot -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $run 'metrics.ndjson'), [byte[]]@(0, 1, 13, 10, 255, 42))
    & tar -czf $fixtureArchive -C $source results
    if ($LASTEXITCODE) { throw 'Fixture archive creation failed.' }
    Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Phase -TunnelPort $TunnelPort
    if ((Get-FileHash (Join-Path $run 'metrics.ndjson')).Hash -ne
        (Get-FileHash (Join-Path $evidenceRoot 'results\fixture\metrics.ndjson')).Hash) {
        throw 'Evidence bytes changed during transfer or extraction.'
    }
    foreach ($case in @('PackFailure', 'CopyFailure', 'PartialGrowingFile')) {
        $fixture.packExit = if ($case -eq 'PackFailure') {2} elseif ($case -eq 'PartialGrowingFile') {1} else {0}
        $fixture.packMessage = if ($case -eq 'PartialGrowingFile') {'tar: metrics.ndjson: file changed as we read it'} else {'fixture failure'}
        $fixture.copyExit = if ($case -eq 'CopyFailure') {1} else {0}
        $rejected = $false
        try {
            Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Phase -TunnelPort $TunnelPort -Partial:($case -eq 'PartialGrowingFile')
        } catch { $rejected = $true }
        if ($rejected -ne ($case -ne 'PartialGrowingFile')) { throw "Evidence failure contract mismatch: $case" }
    }
    $global:LASTEXITCODE = 0
    'Compressed evidence preserves exact raw bytes and reports packing, transfer and live partial-snapshot failures.'
} finally {
    Remove-Item -LiteralPath $stateRoot -Recurse
}
