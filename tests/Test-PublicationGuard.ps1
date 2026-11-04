$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-publication-fixture-$([Guid]::NewGuid().ToString('N'))"
$checker = Join-Path $PSScriptRoot 'Test-Publication.ps1'
$root = Split-Path $PSScriptRoot -Parent
function Expect-PublicationRejected([string] $ExpectedReason) {
    $message = $null
    try { & $checker -WorkspacePath $fixture }
    catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notlike "*$ExpectedReason*") {
        throw "Publication guard did not reject the expected condition: $ExpectedReason"
    }
}
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture '.local') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root '.gitignore') -Destination (Join-Path $fixture '.gitignore')
    $subscription = [Guid]::NewGuid().ToString()
    @{
        subscriptionId = $subscription; tenantId = [Guid]::NewGuid().ToString()
        expectedAccount = 'fixture@example.invalid'; azureConfigDirectory = (Join-Path $fixture 'cli')
        resourceGroups = @{network = 'rg-fixture-net'; workload = 'rg-fixture-work'; operations = 'rg-fixture-ops'}
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture '.local\environment.json')
    $candidate = Join-Path $fixture 'candidate.txt'
    Set-Content -LiteralPath $candidate 'Publishable generic laboratory description.'
    & $checker -WorkspacePath $fixture
    Set-Content -LiteralPath $candidate $subscription
    Expect-PublicationRejected 'known private environment value'
    Set-Content -LiteralPath $candidate "/subscriptions/$([Guid]::NewGuid())/resourceGroups/rg-example"
    Expect-PublicationRejected 'tenant/resource identifier'
    Set-Content -LiteralPath $candidate 'Publishable generic laboratory description.'
    & git init --quiet $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git initialization failed.' }
    & git -C $fixture add --force -- '.local/environment.json'
    if ($LASTEXITCODE -ne 0) { throw 'Fixture tracking setup failed.' }
    Expect-PublicationRejected 'already tracked'
    Write-Output 'Publication guard positive, leaked-context, resource-path and tracked-private-file regressions passed.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
