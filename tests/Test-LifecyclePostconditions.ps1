$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Set-LabLifecycle.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Lifecycle operator does not parse.' }
$block = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq "`$Intent -in @('Suspend', 'Resume')"
}, $true)
if ($null -eq $block) { throw 'Production observed-state verification is missing.' }
$production = [scriptblock]::Create($block.Extent.Text)
$ManifestPath = Join-Path ([IO.Path]::GetTempPath()) 'fixture-manifest.json'
$m = @{outputs = @{'csl-infrastructure' = @{workload = @{value = @{postgresName = 'fixture'}}}}}
$o = @{runnerId = 'fixture'}
$script:LabGroups = @('rg-network', 'rg-workload', 'rg-operations')
$fixture = @{wrongPower = $false; public = $false; unhealthy = $false; proof = $null}
function Start-Sleep([int] $Seconds) { throw 'Fixture prevents waiting on a failed postcondition.' }
function Write-LabJson([string] $Path, [object] $Value) { $fixture.proof = $Value }
function Invoke-LabAz([string[]] $Arguments) {
    $suspended = $Intent -eq 'Suspend'
    $value = switch ($Arguments[0]) {
        postgres { @{
            state = if ($suspended) {'Stopped'} else {'Ready'}
            network = @{publicNetworkAccess = if ($fixture.public) {'Enabled'} else {'Disabled'}}
            availabilityZone = '1'; highAvailability = @{mode = 'ZoneRedundant'; standbyAvailabilityZone = '2'; state = 'Healthy'}
        }}
        vm { @{instanceView = @{statuses = @(@{code = if ($suspended -and -not $fixture.wrongPower) {'PowerState/deallocated'} else {'PowerState/running'}})}} }
        containerapp {
            if ($Arguments[1] -eq 'revision') {
                if ($suspended) { @() } else { @(@{properties = @{active = $true; healthState = if ($fixture.unhealthy) {'Unhealthy'} else {'Healthy'}; provisioningState = 'Provisioned'}}) }
            } else {
                @{properties = @{zoneRedundant = $true; publicNetworkAccess = 'Disabled'; workloadProfiles = @(@{name = 'D4'; minimumCount = if ($suspended) {0} else {3}})}}
            }
        }
        default { throw 'Unexpected postcondition command.' }
    }
    if ($Arguments[0] -eq 'containerapp' -and $Arguments[1] -eq 'revision' -and $suspended) { return '[]' }
    ConvertTo-Json -InputObject $value -Depth 10 -Compress
}
foreach ($case in @('Suspend', 'Resume', 'WrongPower', 'PublicAccess', 'UnhealthyRevision')) {
    $Intent = if ($case -eq 'Resume' -or $case -eq 'UnhealthyRevision') {'Resume'} else {'Suspend'}
    $fixture.wrongPower = $case -eq 'WrongPower'; $fixture.public = $case -eq 'PublicAccess'
    $fixture.unhealthy = $case -eq 'UnhealthyRevision'; $fixture.proof = $null
    $rejected = $false; $reason = $null
    try { . $production } catch { $rejected = $true; $reason = $_.Exception.Message }
    if ($rejected -ne ($case -notin @('Suspend', 'Resume')) -or $null -eq $fixture.proof) {
        throw "Observed lifecycle-state verification mismatch: $case; $reason"
    }
}
'Completed jobs require observed power/database/revision/profile states and unchanged private/cross-zone invariants.'
