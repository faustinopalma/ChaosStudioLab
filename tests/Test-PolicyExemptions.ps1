$ErrorActionPreference = 'Stop'
$previousEnvironment = $env:CSL_ENVIRONMENT_FILE
$previousAzure = $env:AZURE_CONFIG_DIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-exemption-$([Guid]::NewGuid().ToString('N')).json"
$subscription = [Guid]::NewGuid().ToString()
$id = "/subscriptions/$subscription/resourceGroups/rg-test-network/providers/Microsoft.Authorization/policyExemptions/test"
$expected = @{id = $id; assignmentId = '/providers/test/assignment'; referenceIds = @('public-ip')}
@{
    subscriptionId = $subscription; tenantId = [Guid]::NewGuid().ToString()
    expectedAccount = 'test@example.invalid'; azureConfigDirectory = [IO.Path]::GetTempPath()
    deploymentRegion = 'swedencentral'; requiredPolicyExemptions = @($expected)
    resourceGroups = @{network = 'rg-test-network'; workload = 'rg-test-workload'; operations = 'rg-test-operations'}
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture
try {
    $env:CSL_ENVIRONMENT_FILE = $fixture
    . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
    $script:groupExists = 'true'
    $script:records = @(@{
        id = $id; policyAssignmentId = $expected.assignmentId
        policyDefinitionReferenceIds = @('public-ip'); exemptionCategory = 'Waiver'
        expiresOn = [DateTimeOffset]::UtcNow.AddHours(24).ToString('O')
        resourceSelectors = @(@{selectors = @(@{kind = 'resourceType'; 'in' = @('Microsoft.Network/publicIPAddresses')})})
    })
    function Invoke-LabAz([string[]] $Arguments) {
        if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'exists') { return $script:groupExists }
        if ($Arguments[0] -eq 'policy' -and $Arguments[1] -eq 'exemption' -and $Arguments[2] -eq 'list') {
            return (ConvertTo-Json -InputObject $script:records -Depth 15)
        }
        throw 'Startup guard attempted an unexpected operation or mutation.'
    }
    function Expect-Blocked([string] $Reason) {
        $message = $null
        try { Assert-LabPolicyExemptions } catch { $message = $_.Exception.Message }
        if (-not $message -or $message -notlike "*$Reason*" -or
            $message -notlike '*create a new scoped exemption or extend*') {
            throw "Expected actionable startup rejection for $Reason; got $message"
        }
    }
    Assert-LabPolicyExemptions
    $record = $script:records[0]
    $expiry = $record.expiresOn
    $record.Remove('expiresOn')
    Expect-Blocked 'missing required property expiresOn'
    $record.expiresOn = $expiry
    $record.expiresOn = [DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('O')
    Expect-Blocked 'EXPIRED'
    $record.expiresOn = 'invalid'
    Expect-Blocked 'finite expiry'
    $record.expiresOn = [DateTimeOffset]::UtcNow.AddMinutes(30).ToString('O')
    $warnings = @()
    Assert-LabPolicyExemptions -WarningVariable warnings -WarningAction SilentlyContinue
    if ($warnings.Count -ne 1) { throw 'Near-expiry warning is missing.' }
    $record.expiresOn = [DateTimeOffset]::UtcNow.AddHours(24).ToString('O')
    $record.policyDefinitionReferenceIds = @('whole-initiative', 'public-ip')
    Expect-Blocked 'differs'
    $record.policyDefinitionReferenceIds = @('public-ip')
    $script:records = @()
    Expect-Blocked 'missing'
    $script:records = @($record)
    $script:groupExists = 'false'
    Expect-Blocked 'missing'
    $script:groupExists = 'true'
    $script:LabEnvironment.requiredPolicyExemptions = @()
    Assert-LabPolicyExemptions @{policyExemptions = @($expected)}
    $record.expiresOn = [DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('O')
    $rejected = $false
    try { Assert-LabPolicyExemptions @{policyExemptions = @($expected)} } catch { $rejected = $true }
    if (-not $rejected) { throw 'Manifest-only expired exemption was accepted.' }
    $startupState = @{writes = 0; records = $script:records; tenant = $script:LabTenant}
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
        $global:LASTEXITCODE = 0
        if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
            return (ConvertTo-Json @{
                id = $subscription; tenantId = $startupState.tenant; user = @{name = 'test@example.invalid'}
            })
        }
        if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'exists') { return 'true' }
        if ($Arguments[0] -eq 'policy' -and $Arguments[1] -eq 'exemption' -and $Arguments[2] -eq 'list') {
            return (ConvertTo-Json -InputObject $startupState.records -Depth 15)
        }
        $startupState.writes++
        throw 'Expired startup attempted deployment, cleanup or another unexpected Azure operation.'
    }
    $manifestPath = "$fixture.manifest.json"
    Write-LabJson $manifestPath @{
        schemaVersion = 1; architecture = 'linux-app-service'; subscriptionId = $subscription; tenantId = $script:LabTenant
        labId = 'lab-dev01'; deploymentInstanceId = [Guid]::NewGuid().ToString('N')
        resourceIds = @(); policyExemptions = @($expected)
        groups = @($script:LabGroups | ForEach-Object {
            @{name = $_; id = "/subscriptions/$subscription/resourceGroups/$_"}
        })
    }
    $before = Get-Content -LiteralPath $manifestPath -Raw
    foreach ($entrypoint in @('Build-Lab.ps1', 'Initialize-LabMachines')) {
        $blocked = $false
        try {
            $arguments = @{ManifestPath = $manifestPath}
            if ($entrypoint -eq 'Build-Lab.ps1') { $arguments.Step = 'Plan' }
            if ($entrypoint -eq 'Initialize-LabMachines') {
                . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
                Initialize-LabMachines @arguments
            } else {
                & (Join-Path $PSScriptRoot "..\scripts\$entrypoint") @arguments
            }
        } catch {
            $startupError = $_.Exception.Message
            $blocked = $startupError -like '*EXPIRED*'
        }
        if (-not $blocked -or $startupState.writes -ne 0 -or
            (Get-Content -LiteralPath $manifestPath -Raw) -cne $before -or
            (Test-Path -LiteralPath "$manifestPath.lock")) {
            throw "$entrypoint failed to preserve the lab on expired-waiver preflight: $startupError; unexpected operations: $($startupState.writes)"
        }
    }
    Remove-Item -LiteralPath $manifestPath
    Write-Output 'Active, expired, missing, near-expiry, contract-drift and manifest-only exemption tests passed; no writes attempted.'
} finally {
    Remove-Item Function:\az -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath "$fixture.manifest.json") { Remove-Item -LiteralPath "$fixture.manifest.json" }
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzure
    Remove-Item -LiteralPath $fixture
}
