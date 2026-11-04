$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Test-Lab.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Chaos operator does not parse.' }
$blocks = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq "`$Phase -eq 'failover'" -and
        $node.Clauses[0].Item2.Extent.Text.Contains('$workspaceId =')
}, $true))
if ($blocks.Count -ne 1) { throw 'Expected one production discovery preflight.' }
$statements = @()
foreach ($statement in $blocks[0].Clauses[0].Item2.Statements) {
    if ($statement.Extent.Text.StartsWith('& ssh ')) { break }
    $statements += $statement.Extent.Text
}
$production = [scriptblock]::Create($statements -join "`n")
$w = @{chaosScenarioId = '/subscriptions/fixture/resourceGroups/rg-fixture/providers/Microsoft.Chaos/workspaces/fixture/scenarios/fixture'; postgresId = '/subscriptions/fixture/resourceGroups/rg-fixture/providers/Microsoft.DBforPostgreSQL/flexibleServers/fixture'}
$script:LabSubscription = 'fixture'; $script:LabGroups = @('rg-network', 'rg-fixture', 'rg-operations')
$evidenceRoot = 'fixture'
$fixture = @{foreign = $false; missingLocation = $false; failed = $false; missingTarget = $false; posts = 0; polls = 0; saved = $false}
function Start-Sleep([int] $Seconds) {}
function Write-LabJson([string] $Path, [object] $Value) { $fixture.saved = $true }
function Invoke-LabArm([string] $Method, [string] $Uri) {
    if ($Uri -like '*/discoveredResources?*') {
        return @{body = @{value = @(@{properties = @{fullyQualifiedIdentifier = if ($fixture.missingTarget) {'/foreign'} else {$w.postgresId}}})}}
    }
    if ($Uri -like '*/configurations/exact-lab-postgres?*') {
        return @{body = @{properties = @{resourceTargeting = @{include = @{resources = @($w.postgresId)}}}}}
    }
    if ($Method -eq 'Post') {
        $fixture.posts++
        return @{statusCode = 202; headers = @{Location = if ($fixture.missingLocation) { @() } else { @('https://management.azure.com/fixture/discoveries/latest') }}}
    }
    if ($Uri -like '*/discoveries/latest') {
        $fixture.polls++
        return @{statusCode = if ($fixture.polls -eq 1) {202} else {200}; body = @{properties = @{
            status = if ($fixture.failed) {'Failed'} else {'Succeeded'}
            errors = @(@{errorCode = 'FixtureDiscoveryFailure'})
        }}}
    }
    $scopes = @('/subscriptions/fixture/resourceGroups/rg-fixture')
    if ($fixture.foreign) { $scopes += '/foreign' }
    return @{body = @{properties = @{scopes = $scopes}}}
}
foreach ($case in @('Success', 'ForeignScope', 'MissingLocation', 'FailedDiscovery', 'MissingTarget')) {
    $fixture.foreign = $case -eq 'ForeignScope'; $fixture.missingLocation = $case -eq 'MissingLocation'
    $fixture.failed = $case -eq 'FailedDiscovery'; $fixture.posts = 0; $fixture.polls = 0; $fixture.saved = $false
    $fixture.missingTarget = $case -eq 'MissingTarget'
    $rejected = $false
    try { . $production } catch { $rejected = $true }
    if ($rejected -ne ($case -ne 'Success')) { throw "Discovery acceptance mismatch: $case" }
    if ($fixture.foreign -and $fixture.posts) { throw 'Discovery mutated a foreign scope.' }
    if ($case -eq 'Success' -and ($fixture.polls -ne 2 -or -not $fixture.saved)) {
        throw 'Discovery did not await and preserve its terminal result before load startup.'
    }
}
'Production discovery gates exact scope, polling evidence, missing targets and provider failure before load startup.'
