$ErrorActionPreference = 'Stop'
$common = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$null, [ref]$null)
. ([scriptblock]::Create($common.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-LabLifecycleParameters'
}, $true).Extent.Text))
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Register-Controller.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Controller registration script does not parse.' }
$runbookAssignments = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$runbook'
}, $true))
$loops = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'entry'
}, $true))
if ($runbookAssignments.Count -ne 1 -or $loops.Count -ne 1) { throw 'Expected one runbook request and schedule loop.' }
$script:LabLocation = 'swedencentral'
. ([scriptblock]::Create($runbookAssignments[0].Extent.Text))
if ($runbook.properties.runbookType -ne 'PowerShell' -or $runbook.properties.runtimeEnvironment -ne 'csl-ps74') {
    throw 'Explicit PowerShell 7.4 runtime requires the PowerShell runbook type.'
}
$rounding = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -in @('$suspendAt', '$scheduleRemainder', '$suspensionScheduleAt')
}, $true))
if ($rounding.Count -ne 3) { throw 'Expected exact-deadline and service-minute rounding assignments.' }
$code = [scriptblock]::Create(($rounding.Extent.Text -join "`n") + "`n" + $loops[0].Extent.Text)
$script:LabSubscription = [Guid]::NewGuid().ToString()
$script:LabGroups = @('rg-test-network', 'rg-test-workload', 'rg-test-operations')
$aaId = "/subscriptions/$script:LabSubscription/resourceGroups/rg-test-operations/providers/Microsoft.Automation/automationAccounts/aa-test"
$m = @{deploymentInstanceId = [Guid]::NewGuid().ToString('N')}
$o = @{workerGroupName = 'hrg-test'; storageName = 'teststorage'; controlClientId = [Guid]::NewGuid().ToString()}
$readyAt = [DateTimeOffset]::Parse('2030-01-01T00:00:00Z')
$state = @{suspendAtUtc = $readyAt.AddHours(24).ToString('O')}
$bodyPath = 'unused-fixture-path'
$script:bindings = @{}
$script:bindingWrites = 0
function Write-LabJson([string] $Path, [object] $Value) { $script:requestBody = $Value }
function Assert-LabResourceId([string] $Id) {
    if (-not $Id.StartsWith("$aaId/jobSchedules/")) { throw 'Foreign Automation binding.' }
}
function Invoke-LabArm([string] $Method, [string] $Uri) {
    $id = $Uri -replace '^https://management.azure.com', '' -replace '\?.*$', ''
    $matches = @($script:bindings.Values | Where-Object id -EQ $id)
    if ($Method -ne 'Get' -or $matches.Count -ne 1) { throw 'Unexpected binding-detail request.' }
    @{ body = $matches[0] }
}
function Invoke-LabAz([string[]] $Arguments) {
    if ($Arguments[0] -ne 'rest' -or $Arguments[2] -ne 'put') { throw 'Unexpected controller fixture command.' }
    if ($Arguments[4] -match '/jobSchedules/([^?]+)\?') {
        $requestedName = $Matches[1]
        $legacyKey = "$($m.deploymentInstanceId)/csl-lifecycle/$($script:requestBody.properties.schedule.name)"
        $legacyHash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($legacyKey))
        if ($requestedName -eq [Guid]::new([byte[]]$legacyHash[0..15]).ToString()) {
            throw 'Atomic context transport must not reuse deleted legacy association IDs.'
        }
        $name = [Guid]::NewGuid().ToString()
        $script:bindings[$name] = @{id = "$aaId/jobSchedules/$name"; properties = $script:requestBody.properties}
        $script:bindingWrites++
    } elseif ($Arguments[4] -match '/schedules/csl-suspend-deadline\?') {
        $script:scheduledStart = [DateTimeOffset]$script:requestBody.properties.startTime
    }
}
$jobSchedules = @()
. $code
if ($script:bindingWrites -ne 2) { throw 'Initial registration must create exactly two bindings.' }
$originalIds = @($script:bindings.Keys | Sort-Object)
$jobSchedules = @($script:bindings.Values | ForEach-Object {
    @{id = $_.id; properties = @{schedule = $_.properties.schedule; runbook = $_.properties.runbook; runOn = $_.properties.runOn; parameters = $null}}
})
$readyAt = $readyAt.AddHours(1)
$state.suspendAtUtc = $readyAt.AddHours(24).ToString('O')
. $code
if ($script:bindingWrites -ne 2 -or ($originalIds -join ',') -ne (($script:bindings.Keys | Sort-Object) -join ',')) {
    throw 'Resume re-registration created duplicate schedule bindings.'
}
$target = $script:bindings[$originalIds[0]]
$originalContext = $target.properties.parameters.ContextBase64
$target.properties.parameters.ContextBase64 = 'foreigncontext'
$rejected = $false
try { . $code } catch { $rejected = $true }
if (-not $rejected -or $script:bindingWrites -ne 2) { throw 'A drifted lifecycle binding was adopted.' }
$target.properties.parameters.ContextBase64 = $originalContext
$m.deploymentInstanceId = [Guid]::NewGuid().ToString('N')
$aaId = $aaId -replace '/aa-test$', '/aa-next'
$jobSchedules = @()
. $code
if ($script:bindingWrites -ne 4) { throw 'Distinct deployment owners must produce distinct schedule binding IDs.' }
foreach ($timestamp in @('2030-01-01T00:00:00Z', '2030-01-01T00:00:36.4869505Z', '2030-01-01T00:00:59.9999999Z')) {
    $readyAt = [DateTimeOffset]::Parse($timestamp)
    $jobSchedules = @($script:bindings.Values | Where-Object { $_.id.StartsWith("$aaId/") })
    . $code
    $delay = ($script:scheduledStart - $readyAt.AddHours(24)).TotalSeconds
    if ($script:scheduledStart.Ticks % [TimeSpan]::TicksPerMinute -ne 0 -or $delay -lt 0 -or $delay -ge 60) {
        throw 'Service-minute scheduling runs before the exact deadline or waits one extra minute.'
    }
}
'PowerShell 7.4, server-assigned binding IDs, detail reads, drift guards and never-early 24-hour scheduling passed.'
