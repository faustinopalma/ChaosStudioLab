$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Shared lab script does not parse.' }
$functions = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-LabAz'
}, $true))
if ($functions.Count -ne 1) { throw 'Expected one production CLI wrapper.' }
. ([scriptblock]::Create($functions[0].Extent.Text))
function az {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    $script:calls++
    if ($script:calls -le $script:case.failures) {
        $global:LASTEXITCODE = 1
        return $script:case.error
    }
    $global:LASTEXITCODE = 0
    'SUCCESS'
}
function Start-Sleep([double] $Seconds) { $script:delays += $Seconds }
$cases = @(
    @{arguments = @('resource', 'list', '-o', 'json'); failures = 1; error = 'RemoteDisconnected'; calls = 2; rejected = $false}
    @{arguments = @('deployment', 'operation', 'group', 'list', '-g', 'rg-test'); failures = 1; error = 'ConnectionResetError'; calls = 2; rejected = $false}
    @{arguments = @('rest', '--method', 'get', '--url', 'https://example.invalid'); failures = 2; error = 'ConnectionAbortedError'; calls = 3; rejected = $false}
    @{arguments = @('resource', 'show', '--ids', 'test'); failures = 3; error = 'RemoteDisconnected'; calls = 3; rejected = $true}
    @{arguments = @('resource', 'list'); failures = 3; error = 'Forbidden'; calls = 1; rejected = $true}
    @{arguments = @('resource', 'list'); failures = 3; error = 'InvalidArgument'; calls = 1; rejected = $true}
    @{arguments = @('deployment', 'group', 'create', '-n', 'show'); failures = 3; error = 'RemoteDisconnected'; calls = 1; rejected = $true}
    @{arguments = @('vm', 'extension', 'delete', '-n', 'list'); failures = 3; error = 'ConnectionResetError'; calls = 1; rejected = $true}
    @{arguments = @('rest', '--method', 'put', '--url', 'https://example.invalid'); failures = 3; error = 'RemoteDisconnected'; calls = 1; rejected = $true}
    @{arguments = @('rest', '--method'); failures = 3; error = 'InvalidArgument'; calls = 1; rejected = $true}
)
foreach ($script:case in $cases) {
    $script:calls = 0
    $script:delays = @()
    $warnings = @()
    $rejected = $false
    try {
        $result = Invoke-LabAz -Arguments $script:case.arguments -WarningVariable warnings -WarningAction SilentlyContinue
        if ($result -ne 'SUCCESS') { throw 'Unexpected successful CLI result.' }
    } catch { $rejected = $true }
    $expectedDelays = switch ($script:case.calls) { 1 { '' }; 2 { '2' }; 3 { '2,4' } }
    if ($rejected -ne $script:case.rejected -or $script:calls -ne $script:case.calls -or
        ($script:delays -join ',') -ne $expectedDelays -or $warnings.Count -ne $script:case.calls - 1) {
        throw 'CLI transport handling retried a mutation/nontransport error or violated its bounded read-only contract.'
    }
}
$global:LASTEXITCODE = 0
'Read-only transport retries, explicit warnings, terminal errors and nonretryable mutations passed.'
