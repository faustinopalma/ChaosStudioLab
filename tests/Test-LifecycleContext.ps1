$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$common = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$null, [ref]$null)
. ([scriptblock]::Create($common.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-LabLifecycleParameters'
}, $true).Extent.Text))
$runbook = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\runbooks\Lifecycle.ps1'), [ref]$null, [ref]$null)
if ($runbook.ParamBlock.Parameters.Count -ne 1) { throw 'Hybrid Worker must receive one atomic lifecycle context.' }
$prefix = @()
foreach ($statement in $runbook.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { break }
    $prefix += $statement.Extent.Text
}
$decode = [scriptblock]::Create($runbook.ParamBlock.Extent.Text + "`n" + ($prefix -join "`n"))
$script:LabSubscription = [Guid]::NewGuid().ToString()
$script:LabGroups = @('rg-fixture-net', 'rg-fixture-work', 'rg-fixture-ops')
$operations = @{ storageName = 'fixturestorage'; controlClientId = [Guid]::NewGuid().ToString() }
$parameters = New-LabLifecycleParameters $operations Resume
if ($parameters.Count -ne 1 -or
    $parameters.ContextBase64 -ne (New-LabLifecycleParameters $operations Resume).ContextBase64) {
    throw 'Lifecycle serialization must be singular and deterministic.'
}
. $decode @parameters
if ($SubscriptionId -ne $script:LabSubscription -or $StorageName -ne $operations.storageName -or
    $ControlClientId -ne $operations.controlClientId -or $Intent -ne 'Resume' -or
    ($groups -join ',') -ne ($script:LabGroups -join ',')) { throw 'Lifecycle context changed target meaning.' }
foreach ($case in @('BadSchema', 'BadSubscription', 'DuplicateGroup', 'BadIntent', 'MissingStorage')) {
    $context = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parameters.ContextBase64)) | ConvertFrom-Json -AsHashtable
    switch ($case) {
        BadSchema { $context.schemaVersion = 2 }
        BadSubscription { $context.SubscriptionId = 'invalid' }
        DuplicateGroup { $context.NetworkResourceGroupName = $context.WorkloadResourceGroupName }
        BadIntent { $context.Intent = 'Destroy' }
        MissingStorage { $context.Remove('StorageName') }
    }
    $bad = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($context | ConvertTo-Json -Compress)))
    $rejected = $false
    try { . $decode -ContextBase64 $bad } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid lifecycle context accepted: $case." }
}
'Single-parameter lifecycle transport preserves exact scope and rejects invalid context before identity or Azure access.'
. ([scriptblock]::Create($runbook.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Arm'
}, $true).Extent.Text))
function Assert-Target([string] $Id) { if ($Id -ne '/fixture') { throw 'Foreign fixture target.' } }
function Renew-Lock {}
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $TimeoutSec, $ContentType, $Body)
    if ($ContentType -ne 'application/json') { throw 'Bodyless ARM actions must declare the JSON media type.' }
    if ($Method -eq 'Patch' -and ($Body | ConvertFrom-Json).properties.minimumCount -ne 0) { throw 'ARM JSON payload changed.' }
}
$armHeaders = @{}
Arm Post '/fixture' 'fixture-version'
Arm Patch '/fixture' 'fixture-version' @{ properties = @{ minimumCount = 0 } }
'Runbook ARM requests use JSON content type for both bodyless actions and explicit payloads.'
. ([scriptblock]::Create($common.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-LabArm'
}, $true).Extent.Text))
function Assert-LabResourceId([string] $Id) { if ($Id -ne '/fixture') { throw 'Foreign ARM fixture.' } }
function Invoke-LabAz([string[]] $Arguments) { 'synthetic-token' }
function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $TimeoutSec, $ContentType, $Body)
    if ($ContentType -ne 'application/json' -or $Headers.Authorization -ne 'Bearer synthetic-token') {
        throw 'Operator ARM media type or authentication changed.'
    }
    if ($Method -eq 'Patch' -and ($Body | ConvertFrom-Json).properties.isEnabled -ne $false) {
        throw 'Structured cleanup JSON was altered.'
    }
    @{ StatusCode = 200; Headers = @{}; Content = '{}' }
}
Invoke-LabArm Post 'https://management.azure.com/fixture' | Out-Null
Invoke-LabArm Patch 'https://management.azure.com/fixture' @{ properties = @{ isEnabled = $false } } | Out-Null
'Operator ARM requests preserve structured cleanup JSON and explicit media type without native-shell quoting.'
