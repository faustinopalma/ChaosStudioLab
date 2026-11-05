[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $StateDirectory,
    [Parameter(Mandatory)][string] $PreviousManifestPath,
    [ValidateRange(10, 300)][int] $CommandTimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $env:CSL_ENVIRONMENT_FILE) {
    throw 'Select the approved private environment explicitly with CSL_ENVIRONMENT_FILE.'
}
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')

function Assert-PreflightRead {
    param([string[]] $Arguments)
    $prefix = ($Arguments | Select-Object -First 2) -join ' '
    if ($prefix -in @('account show', 'group exists', 'resource list', 'webapp list-runtimes')) { return }
    if ($prefix -eq 'policy exemption' -and $Arguments.Count -ge 3 -and $Arguments[2] -eq 'list') { return }
    if ($prefix -eq 'rest --method' -and $Arguments.Count -ge 5 -and $Arguments[2] -eq 'get' -and
        $Arguments[3] -eq '--url') {
        $uri = [Uri]$Arguments[4]
        $root = "/subscriptions/$script:LabSubscription/providers/"
        if ($uri.Scheme -eq 'https' -and $uri.Host -eq 'management.azure.com' -and
            $uri.AbsolutePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and
            -not $uri.UserInfo -and $uri.IsDefaultPort) { return }
    }
    throw 'Preflight permits only its explicit read-only Azure CLI operations.'
}

function Invoke-PreflightAz {
    param([string[]] $Arguments)
    Assert-PreflightRead $Arguments
    $encodedArguments = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Arguments -Compress)))
    $child = @"
`$ErrorActionPreference = 'Stop'
`$arguments = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedArguments')) | ConvertFrom-Json
& az @arguments --only-show-errors
exit `$LASTEXITCODE
"@
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand',
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child)))) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Cannot start the bounded read-only Azure CLI process.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($CommandTimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Read-only Azure CLI command exceeded $CommandTimeoutSeconds seconds; its process tree was stopped."
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Read-only Azure CLI failed ($($process.ExitCode)): $errorOutput" }
        if ($errorOutput) { Write-Warning $errorOutput.Trim() }
        return $output
    } finally { $process.Dispose() }
}

function Assert-PreflightCatalog {
    param([hashtable] $Catalog)
    foreach ($expected in @(
        @{name = 'microsoft-appservice-killprocess'; canonical = 'urn:csci:microsoft:appservice:killprocess/1.0.0'
            target = 'Microsoft.Web/sites'; parameters = @('ProcessName', 'InstanceIds', 'Zones')}
        @{name = 'microsoft-azurepostgresql-failover'; canonical = 'urn:csci:microsoft:azurepostgresql:failover/1.0.0'
            target = 'Microsoft.DBforPostgreSQL/flexibleServers'; parameters = @('FailoverMode', 'RestoreOnStop', 'SkipIneligibleServers')}
    )) {
        $matches = @($Catalog.value | Where-Object name -EQ $expected.name)
        if ($matches.Count -ne 1) { throw "Missing or ambiguous native Action: $($expected.name)." }
        $action = $matches[0].properties
        if ($action.canonicalId -cne $expected.canonical -or
            $expected.target -notin @($action.supportedTargetTypes | ForEach-Object targetType)) {
            throw "Native Action canonical ID/target contract changed: $($expected.name)."
        }
        foreach ($parameter in $expected.parameters) {
            if (-not $action.parametersSchema.properties.ContainsKey($parameter)) {
                throw "Missing native Action parameter $parameter in $($expected.name)."
            }
        }
        if ($expected.name -eq 'microsoft-appservice-killprocess') {
            if ($action.actionType -ne 'Discrete') { throw 'Process crash must retain discrete fault semantics.' }
            foreach ($selector in @('InstanceIds', 'Zones')) {
                $schema = $action.parametersSchema.properties[$selector]
                if ('array' -notin @($schema.type) -or $schema.items.type -ne 'string') {
                    throw "Unqualified native selector shape: $selector."
                }
            }
            if ($action.parametersSchema.properties.ProcessName.description -notmatch '\bLinux\b') {
                throw 'Linux process eligibility remains unqualified by the current regional schema.'
            }
        }
    }
}

function Invoke-AppServicePreflight {
    $root = [IO.Path]::GetFullPath($StateDirectory)
    $privateRoot = [IO.Path]::GetFullPath((Join-Path $script:LabRoot '.local')) + [IO.Path]::DirectorySeparatorChar
    if (-not $root.StartsWith($privateRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-Path -LiteralPath $root)) {
        throw 'Use a fresh, nonexistent directory inside the ignored .local folder. Previous evidence is never overwritten.'
    }
    & git -C $script:LabRoot check-ignore --no-index --quiet -- $root
    if ($LASTEXITCODE -ne 0) { throw 'The preflight state directory must be excluded from publication.' }
    $previous = Read-LabManifest ([IO.Path]::GetFullPath($PreviousManifestPath))
    $account = Invoke-PreflightAz @('account', 'show', '-o', 'json') | ConvertFrom-Json -AsHashtable
    if ($account.id -ine $script:LabSubscription -or $account.tenantId -ine $script:LabTenant -or
        $account.user.name -ine $script:LabEnvironment.expectedAccount) {
        throw 'The selected CLI profile differs from the approved account, tenant or subscription. No login or PIM was attempted.'
    }
    New-Item -ItemType Directory -Path $root | Out-Null
    $manifestPath = Join-Path $root 'manifest.json'
    $reportPath = Join-Path $root 'preflight.json'
    $started = [DateTimeOffset]::UtcNow
    $manifest = @{
        schemaVersion = 1; architecture = 'linux-app-service'; labId = 'lab-dev01'
        subscriptionId = $script:LabSubscription; tenantId = $script:LabTenant
        deploymentInstanceId = [Guid]::NewGuid().ToString('N'); createdAtUtc = $started.ToString('O')
        groups = @($script:LabGroups | ForEach-Object {
            @{name = $_; id = "/subscriptions/$script:LabSubscription/resourceGroups/$_"}
        })
        resourceIds = @(); outputs = @{}; status = 'PREFLIGHT_ONLY'
        previousManifestPath = [IO.Path]::GetFullPath($PreviousManifestPath)
        policyExemptions = @($script:LabEnvironment.requiredPolicyExemptions)
    }
    Write-LabJson $manifestPath $manifest
    $checks = [Collections.Generic.List[object]]::new()
    $cases = [ordered]@{
        'old-group-absence' = {
            $groups = @(foreach ($group in $script:LabGroups) {
                $exists = (Invoke-PreflightAz @('group', 'exists', '-n', $group, '-o', 'tsv')).Trim()
                if ($exists -notin @('true', 'false')) { throw 'Unrecognized resource-group existence response.' }
                @{name = $group; exists = $exists -eq 'true'}
            })
            Write-LabJson (Join-Path $root 'old-group-absence.json') $groups
            if (@($groups | Where-Object exists).Count) {
                throw 'Previous exact scope remains occupied; no deletion, adoption or deployment was attempted.'
            }
        }
        'resource-baseline' = {
            $baseline = Invoke-PreflightAz @('resource', 'list', '--subscription', $script:LabSubscription,
                '--query', '[].{id:id,type:type,group:resourceGroup}', '-o', 'json') | ConvertFrom-Json -AsHashtable
            Write-LabJson (Join-Path $root 'preexisting-resources.json') @($baseline)
        }
        'postgresql-regional-ha' = {
            $capabilities = Invoke-PreflightAz @('rest', '--method', 'get', '--url',
                "https://management.azure.com/subscriptions/$script:LabSubscription/providers/Microsoft.DBforPostgreSQL/locations/$script:LabLocation/capabilities?api-version=2024-08-01",
                '-o', 'json') | ConvertFrom-Json -AsHashtable
            Write-LabJson (Join-Path $root 'postgresql-capabilities.json') $capabilities
            $entries = @($capabilities.value)
            if ($entries.Count -ne 1 -or $entries[0].restricted -ne 'Disabled' -or
                $entries[0].zoneRedundantHaSupported -ne 'Enabled') {
                throw 'Subscription-level PostgreSQL zone-redundant HA is unavailable or unqualified.'
            }
        }
        'native-action-catalog' = {
            $catalog = @{value = @()}
            $page = "https://management.azure.com/subscriptions/$script:LabSubscription/providers/Microsoft.Chaos/locations/$script:LabChaosLocation/actions?api-version=2026-08-01-preview"
            $pageNumber = 0
            do {
                if (++$pageNumber -gt 10) { throw 'Native Action catalog exceeded ten bounded pages.' }
                $response = Invoke-PreflightAz @('rest', '--method', 'get', '--url', $page, '-o', 'json') |
                    ConvertFrom-Json -AsHashtable
                $catalog.value += @($response.value)
                $page = if ($response.ContainsKey('nextLink')) { $response.nextLink } else { $null }
            } while ($page)
            Write-LabJson (Join-Path $root 'native-action-catalog.json') $catalog
            Assert-PreflightCatalog $catalog
        }
        'linux-runtime' = {
            $runtimes = @(Invoke-PreflightAz @('webapp', 'list-runtimes', '--os', 'linux', '-o', 'json') |
                ConvertFrom-Json -AsHashtable)
            Write-LabJson (Join-Path $root 'linux-runtimes.json') $runtimes
            Assert-LabLinuxRuntime $runtimes
        }
        'required-policy-exemptions' = {
            # Reuse the existing missing/expired/drift guard with bounded read-only transport.
            function Invoke-LabAz { param([string[]] $Arguments) Invoke-PreflightAz $Arguments }
            Assert-LabPolicyExemptions $manifest
        }
    }
    foreach ($entry in $cases.GetEnumerator()) {
        $stage = [DateTimeOffset]::UtcNow
        Write-Information "[$($stage.ToString('O'))] Preflight: $($entry.Key) (CLI output is buffered; each command has a $CommandTimeoutSeconds-second deadline)." -InformationAction Continue
        $check = @{name = $entry.Key; startedAtUtc = $stage.ToString('O'); status = 'PASS'}
        try { & $entry.Value }
        catch {
            $check.status = 'BLOCKED'
            $check.reason = $_.Exception.Message
            Write-Warning "$($entry.Key): $($check.reason)"
        }
        $check.elapsedSeconds = ([DateTimeOffset]::UtcNow - $stage).TotalSeconds
        $checks.Add($check)
        Write-LabJson (Join-Path $root 'checks.json') @($checks.ToArray())
    }
    $blocked = @($checks | Where-Object status -NE 'PASS')
    $reason = if ($blocked.Count) { ($blocked | ForEach-Object { "$($_.name): $($_.reason)" }) -join '; ' }
        else { 'Source refactor, ARM validation/previews, actual Linux app/private-SCM/three-zone readiness and native effects have not been qualified.' }
    $tests = @(foreach ($id in @('BASE-001', 'HA-APP-001', 'HA-APP-ZONE-001', 'HA-DB-001', 'HA-COMBINED-001', 'HA-AZ-001')) {
        @{id = $id; verdict = 'BLOCKED'; executed = $false; reason = if ($id -eq 'HA-AZ-001') {
            'No qualifying correlated real-zone injection/effect evidence. Discrete process crashes cannot establish this result.'
        } else { $reason }}
    })
    $manifest.status = if ($blocked.Count) { 'PREFLIGHT_BLOCKED' } else { 'PREFLIGHT_PASSED' }
    Write-LabJson $manifestPath $manifest
    $report = @{
        startedAtUtc = $started.ToString('O'); finishedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        preflightVerdict = if ($blocked.Count) { 'BLOCKED' } else { 'PASS' }
        suiteVerdict = 'BLOCKED'; tests = $tests; checks = @($checks.ToArray())
        timings = @{preflightSeconds = ([DateTimeOffset]::UtcNow - $started).TotalSeconds
            provisioningSeconds = 0; troubleshootingSeconds = 0; measurementSeconds = 0}
        deploymentReady = $false; azureMutationsAttempted = 0
        cleanupLimitations = @('Recoverable vaults/purge and historical baseline attribution have not been certified.',
            'Absence checks cover the three exact configured groups; service-managed group cleanup is not independently recertified.')
        runtimeQualification = 'Catalog candidate only; actual runtime publication and native Action effects remain unqualified.'
        placementQualification = 'No actual plan or instance/health/traffic evidence; three-zone readiness is BLOCKED.'
        privateScmQualification = 'Documented private DNS/SCM path; no actual private publication or denial probes performed.'
        manualDeletionOrder = @('workload', 'operations', 'network')
        previousDeploymentInstanceId = $previous.deploymentInstanceId
    }
    Write-LabJson $reportPath $report
    Write-Information "Preflight $($report.preflightVerdict); suite BLOCKED. Evidence: $root. No provisioning, faults, cleanup or lifecycle operations were attempted." -InformationAction Continue
    if ($blocked.Count) { throw "BLOCKED: inspect $reportPath. Resources and governance were left unchanged." }
}

Invoke-AppServicePreflight
