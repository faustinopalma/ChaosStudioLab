$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$path = Join-Path $PSScriptRoot '..\scripts\Test-AppServicePreflight.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Assert-PreflightRead', 'Invoke-PreflightAz', 'Assert-PreflightCatalog', 'Invoke-AppServicePreflight')) {
    $functions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($functions.Count -ne 1) { throw "Expected one production function $name." }
    . ([scriptblock]::Create($functions[0].Extent.Text))
}
$script:LabSubscription = [Guid]::NewGuid().ToString()
$script:LabTenant = [Guid]::NewGuid().ToString()
$script:LabLocation = 'swedencentral'
$script:LabGroups = @('rg-test-network', 'rg-test-workload', 'rg-test-operations')
$script:LabEnvironment = @{
    expectedAccount = 'test@example.invalid'
    requiredPolicyExemptions = @(@{
        id = "/subscriptions/$script:LabSubscription/resourceGroups/rg-test-network/providers/Microsoft.Authorization/policyExemptions/test"
        assignmentId = '/providers/test/assignment'; referenceIds = @('public-ip')
    })
}
$script:LabEnvironmentPath = 'private-test-environment.json'
$script:LabRoot = Join-Path ([IO.Path]::GetTempPath()) "csl-preflight-$([Guid]::NewGuid().ToString('N'))"
$StateDirectory = Join-Path $script:LabRoot '.local\new-run'
$PreviousManifestPath = Join-Path $script:LabRoot '.local\old-manifest.json'
$CommandTimeoutSeconds = 30
$script:fixtureCatalog = @{value = @(
    @{name = 'microsoft-appservice-killprocess'; properties = @{
        canonicalId = 'urn:csci:microsoft:appservice:killprocess/1.0.0'; actionType = 'Discrete'
        supportedTargetTypes = @(@{targetType = 'Microsoft.Web/sites'})
        parametersSchema = @{properties = @{
            ProcessName = @{description = 'Main worker: w3wp for Windows, dotnet/node for Linux.'}
            InstanceIds = @{type = @('array', 'null'); items = @{type = 'string'}}
            Zones = @{type = @('array', 'null'); items = @{type = 'string'}}
        }}
    }}
    @{name = 'microsoft-azurepostgresql-failover'; properties = @{
        canonicalId = 'urn:csci:microsoft:azurepostgresql:failover/1.0.0'
        supportedTargetTypes = @(@{targetType = 'Microsoft.DBforPostgreSQL/flexibleServers'})
        parametersSchema = @{properties = @{FailoverMode = @{}; RestoreOnStop = @{}; SkipIneligibleServers = @{}}}
    }}
)}
function Expect-Rejected([scriptblock] $Action, [string] $Pattern) {
    $message = $null
    try { & $Action } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notlike $Pattern) { throw "Expected rejection $Pattern; got $message" }
}
Assert-PreflightRead @('group', 'exists', '-n', 'rg-test-network')
Assert-PreflightRead @('rest', '--method', 'get', '--url',
    "https://management.azure.com/subscriptions/$script:LabSubscription/providers/Microsoft.Chaos/locations/swedencentral/actions")
foreach ($arguments in @(
    @('group', 'delete', '-n', 'rg-test-network'),
    @('policy', 'exemption', 'create'),
    @('rest', '--method', 'post', '--url', 'https://management.azure.com/'),
    @('rest', '--method', 'get', '--url', 'https://example.invalid/'),
    @('account', 'get-access-token'),
    @('webapp', 'restart')
)) { Expect-Rejected { Assert-PreflightRead $arguments } '*only its explicit read-only*' }
Assert-PreflightCatalog $script:fixtureCatalog
$kill = $script:fixtureCatalog.value[0].properties
$kill.parametersSchema.properties.Zones.type = 'string'
Expect-Rejected { Assert-PreflightCatalog $script:fixtureCatalog } '*selector shape*'
$kill.parametersSchema.properties.Zones.type = @('array', 'null')
$kill.parametersSchema.properties.ProcessName.description = 'No OS statement.'
Expect-Rejected { Assert-PreflightCatalog $script:fixtureCatalog } '*Linux process eligibility*'
$kill.parametersSchema.properties.ProcessName.description = 'dotnet/node for Linux'
$kill.canonicalId = 'unqualified-action'
Expect-Rejected { Assert-PreflightCatalog $script:fixtureCatalog } '*canonical ID*'
$kill.canonicalId = 'urn:csci:microsoft:appservice:killprocess/1.0.0'

New-Item -ItemType Directory -Path (Split-Path $PreviousManifestPath -Parent) -Force | Out-Null
$originalPath = $env:PATH
$originalMode = $env:CSL_PREFLIGHT_TEST_MODE
try {
    $fakeCli = Join-Path $script:LabRoot 'fake-cli'
    New-Item -ItemType Directory -Path $fakeCli | Out-Null
    @'
if ($env:CSL_PREFLIGHT_TEST_MODE -eq 'timeout') { Start-Sleep 30 }
if ($env:CSL_PREFLIGHT_TEST_MODE -eq 'error') {
    [Console]::Error.WriteLine('explicit transport fixture failure')
    exit 7
}
'{"transport":"bounded-output"}'
'@ | Set-Content -LiteralPath (Join-Path $fakeCli 'fake-az.ps1')
    ('@"{0}" -NoLogo -NoProfile -NonInteractive -File "%~dp0fake-az.ps1"' -f (Get-Process -Id $PID).Path) |
        Set-Content -LiteralPath (Join-Path $fakeCli 'az.cmd')
    $env:PATH = "$fakeCli;$originalPath"
    $env:CSL_PREFLIGHT_TEST_MODE = 'success'
    $result = Invoke-PreflightAz @('account', 'show')
    if (($result | ConvertFrom-Json).transport -ne 'bounded-output') { throw 'Bounded transport lost stdout.' }
    $env:CSL_PREFLIGHT_TEST_MODE = 'error'
    Expect-Rejected { Invoke-PreflightAz @('account', 'show') } '*explicit transport fixture failure*'
    $env:CSL_PREFLIGHT_TEST_MODE = 'timeout'
    $CommandTimeoutSeconds = 1
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Expect-Rejected { Invoke-PreflightAz @('account', 'show') } '*exceeded 1 seconds*'
    if ($timer.Elapsed.TotalSeconds -gt 8) { throw 'The CLI process deadline was not enforced.' }
    $CommandTimeoutSeconds = 30
    $env:PATH = $originalPath
    $env:CSL_PREFLIGHT_TEST_MODE = $originalMode
    $common = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
    foreach ($name in @('Assert-LabResourceId', 'Assert-LabPolicyExemptions')) {
        $definition = @($common.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        if ($definition.Count -ne 1) { throw "Missing shared production guard $name." }
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
    $oldContent = '{"deploymentInstanceId":"old-evidence-must-remain-unchanged"}'
    Set-Content -LiteralPath $PreviousManifestPath -Value $oldContent -NoNewline
    function git { $global:LASTEXITCODE = 0 }
    function Write-LabJson([string] $Path, [object] $Value) {
        ConvertTo-Json -InputObject $Value -Depth 50 | Set-Content -LiteralPath $Path
    }
    function Read-LabManifest([string] $Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    $script:invocations = [Collections.Generic.List[string]]::new()
    function Invoke-PreflightAz([string[]] $Arguments) {
        Assert-PreflightRead $Arguments
        $script:invocations.Add(($Arguments -join ' '))
        $value = switch (($Arguments | Select-Object -First 2) -join ' ') {
            'account show' { @{id = $script:LabSubscription; tenantId = $script:LabTenant; user = @{name = 'test@example.invalid'}} }
            'group exists' { return 'false' }
            'resource list' { @() }
            'webapp list-runtimes' { @(@{config = 'DOTNETCORE|10.0'; os = 'Linux'; support = 'Active'}) }
            'rest --method' {
                if ($Arguments[4] -like '*/capabilities?*') { @{value = @(@{restricted = 'Disabled'; zoneRedundantHaSupported = 'Enabled'})} }
                else { $script:fixtureCatalog }
            }
            default { throw 'Unexpected mocked CLI operation.' }
        }
        ConvertTo-Json -InputObject $value -Depth 30
    }
    Expect-Rejected { Invoke-AppServicePreflight } 'BLOCKED: inspect*'
    $report = Get-Content (Join-Path $StateDirectory 'preflight.json') -Raw | ConvertFrom-Json
    $manifest = Get-Content (Join-Path $StateDirectory 'manifest.json') -Raw | ConvertFrom-Json
    if ($report.preflightVerdict -ne 'BLOCKED' -or $report.suiteVerdict -ne 'BLOCKED' -or
        $report.azureMutationsAttempted -ne 0 -or $report.deploymentReady -or
        @($report.checks | Where-Object status -EQ 'PASS').Count -ne 5 -or
        @($report.tests).Count -ne 6 -or @($report.tests | Where-Object { $_.executed -or $_.verdict -ne 'BLOCKED' }).Count -or
        $manifest.deploymentInstanceId -eq 'old-evidence-must-remain-unchanged' -or
        $manifest.resourceIds.Count -or $manifest.status -ne 'PREFLIGHT_BLOCKED' -or
        (Get-Content $PreviousManifestPath -Raw) -cne $oldContent) {
        throw 'Preflight violated its fresh-manifest, safety, evidence or separate-verdict contract.'
    }
    $before = $script:invocations.Count
    Expect-Rejected { Invoke-AppServicePreflight } '*fresh, nonexistent directory*'
    if ($before -ne $script:invocations.Count) { throw 'Existing state rejection queried Azure.' }
    'Read-only operations, regional Linux schemas, fresh evidence, bounded-stage reporting and six separate BLOCKED verdicts passed.'
} finally {
    $env:PATH = $originalPath
    $env:CSL_PREFLIGHT_TEST_MODE = $originalMode
    Remove-Item -LiteralPath $script:LabRoot -Recurse -Force
    if (Test-Path Function:\git) { Remove-Item Function:\git }
}
