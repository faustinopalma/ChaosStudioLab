$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:LabRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($env:CSL_ENVIRONMENT_FILE)) {
    throw 'Explicitly select the approved private environment with CSL_ENVIRONMENT_FILE.'
}
$environmentPath = $env:CSL_ENVIRONMENT_FILE
if (-not (Test-Path -LiteralPath $environmentPath -PathType Leaf)) {
    throw 'Missing local environment configuration. Copy config\environment.example.json to .local\environment.json and supply the approved context.'
}
$script:LabEnvironment = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json -AsHashtable
$script:LabEnvironmentPath = [IO.Path]::GetFullPath($environmentPath)
foreach ($key in @('subscriptionId', 'tenantId', 'expectedAccount', 'azureConfigDirectory', 'deploymentRegion', 'resourceGroups')) {
    if (-not $script:LabEnvironment.ContainsKey($key) -or -not $script:LabEnvironment[$key]) {
        throw "Local environment configuration is missing $key."
    }
}
foreach ($key in @('subscriptionId', 'tenantId')) {
    $parsedId = [Guid]::Empty
    if (-not [Guid]::TryParse($script:LabEnvironment[$key], [ref]$parsedId) -or $parsedId -eq [Guid]::Empty) {
        throw "Local environment configuration contains an invalid $key."
    }
}
$script:LabSubscription = $script:LabEnvironment.subscriptionId
$script:LabTenant = $script:LabEnvironment.tenantId
$script:LabLocation = $script:LabEnvironment.deploymentRegion
$script:LabChaosLocation = if ($script:LabEnvironment.ContainsKey('chaosWorkspaceRegion')) {
    $script:LabEnvironment.chaosWorkspaceRegion
} else { $script:LabLocation }
$script:LabOperationsLocation = if ($script:LabEnvironment.ContainsKey('operationsRegion')) {
    $script:LabEnvironment.operationsRegion
} else { $script:LabLocation }
foreach ($region in @($script:LabLocation, $script:LabChaosLocation, $script:LabOperationsLocation)) {
    if ($region -cnotmatch '^[a-z][a-z0-9]+$') {
        throw 'Each configured Azure region must be a lowercase location name. Qualify its live service, allocation and zone capabilities before deployment.'
    }
}
$script:LabGroups = @(
    foreach ($role in @('network', 'workload', 'operations')) {
        $name = $script:LabEnvironment.resourceGroups[$role]
        if ($name -notmatch '^rg-[a-zA-Z0-9._()-]{1,85}$') {
            throw "Local environment configuration contains an invalid $role resource group."
        }
        $name
    }
)
if (@($script:LabGroups | Sort-Object -Unique).Count -ne 3) {
    throw 'The local environment must specify three distinct resource groups.'
}
$env:AZURE_CONFIG_DIR = $script:LabEnvironment.azureConfigDirectory

function Invoke-LabAz {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $readOnly = $false
    foreach ($argument in $Arguments) {
        if ($argument.StartsWith('-')) { break }
        $readOnly = $argument -in @('show', 'list', 'exists', 'what-if', 'validate', 'get-access-token')
    }
    if ($Arguments[0] -eq 'rest') {
        $methodIndex = [Array]::IndexOf($Arguments, '--method')
        $readOnly = $methodIndex -ge 0 -and $methodIndex + 1 -lt $Arguments.Count -and $Arguments[$methodIndex + 1] -eq 'get'
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $result = & az @Arguments --only-show-errors 2>&1
        $message = $result -join [Environment]::NewLine
        if ($LASTEXITCODE -eq 0) { return $message }
        if (-not $readOnly -or $attempt -eq 3 -or
            $message -notmatch 'RemoteDisconnected|ConnectionResetError|ConnectionAbortedError') {
            throw "Azure CLI failed ($LASTEXITCODE): $message"
        }
        Write-Warning "Read-only Azure CLI transport disconnected; retrying ($attempt/3)."
        Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
    }
}

function Get-LabSshOptions {
    param([hashtable] $Manifest, [string] $StateRoot)
    @('-i', $Manifest.sshKeyPath, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20',
        '-o', 'ConnectionAttempts=1', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3',
        '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$(Join-Path $StateRoot 'known-hosts')")
}

function Sync-LabTestTooling {
    param([string] $ManifestPath, [int] $TunnelPort)
    $manifest = Read-LabManifest $ManifestPath
    $stateRoot = Split-Path $ManifestPath -Parent
    $options = @(Get-LabSshOptions $manifest $stateRoot)
    $id = [Guid]::NewGuid().ToString('N')
    $archiveName = "test-tools-$id.zip"
    $checksumName = "test-tools-$id.sha256"
    $archivePath = Join-Path $stateRoot $archiveName
    $started = [DateTimeOffset]::UtcNow
    $files = @(
        'scripts\runner\test.ps1', 'scripts\runner\verify.ps1'
        'scripts\runner\qualify-app.ps1', 'scripts\runner\observe.ps1'
        'tests\load\run.ps1', 'tests\load\scenario.js'
        'tests\load\evaluate-durability.ps1', 'tests\load\evaluate-recovery.ps1'
    )
    $checksums = @()
    try {
        $archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($relative in $files) {
                $path = Join-Path $script:LabRoot $relative
                $entry = $relative.Replace('\', '/')
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $path, $entry) | Out-Null
                $checksums += @{path=$entry;sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()}
            }
            $writer = [IO.StreamWriter]::new($archive.CreateEntry($checksumName).Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write(($checksums | ForEach-Object { "$($_.sha256)  $($_.path)" }) -join "`n") }
            finally { $writer.Dispose() }
        } finally { $archive.Dispose() }
        $archiveHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Information "[$($started.ToString('O'))] Synchronizing eight current private measurement/observer/retention tools and verifying every source checksum." -InformationAction Continue
        & scp @options -P $TunnelPort $archivePath "csloperator@127.0.0.1:csl/$archiveName"
        if ($LASTEXITCODE -ne 0) { throw 'Private measurement-tool package transfer failed.' }
        & ssh @options -p $TunnelPort 'csloperator@127.0.0.1' "cd ~/csl && unzip -oq $archiveName && sha256sum --quiet --check $checksumName && rm -- $archiveName $checksumName"
        if ($LASTEXITCODE -ne 0) { throw 'Private measurement-tool extraction or source checksum verification failed.' }
        return @{startedAtUtc=$started.ToString('O');completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
            archiveSha256=$archiveHash;files=$checksums}
    } finally {
        if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
    }
}

function Save-LabRunnerEvidence {
    param([string] $ManifestPath, [ValidateSet('warmup', 'baseline', 'app-instance', 'app-zone', 'failover', 'combined')][string] $Phase,
        [int] $TunnelPort, [switch] $Partial)
    $manifest = Read-LabManifest $ManifestPath
    $stateRoot = Split-Path $ManifestPath -Parent
    $evidenceRoot = Join-Path $stateRoot 'evidence'
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $sshOptions = @(Get-LabSshOptions $manifest $stateRoot)
    $sshArgs = $sshOptions + @('-p', [string]$TunnelPort, 'csloperator@127.0.0.1')
    $name = "$Phase-evidence.tgz"
    $archive = Join-Path $stateRoot $name
    $packed = & ssh @sshArgs "cd ~/csl && tar -czf $name results" 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($Partial -and $LASTEXITCODE -eq 1 -and ($packed -join "`n") -like '*file changed as we read it*') {
            Write-Warning 'Partial evidence was archived while the failed-stage workload was still writing.'
        } else { throw "Private evidence compression failed: $($packed -join "`n")" }
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $copyOutput = & scp @sshOptions -P $TunnelPort "csloperator@127.0.0.1:csl/$name" $archive 2>&1
        if ($LASTEXITCODE -eq 0) { break }
        $message = $copyOutput -join [Environment]::NewLine
        if ($attempt -eq 3 -or $message -notmatch 'Connection timed out|Connection reset|Connection closed' -or
            $message -match 'Permission denied|Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED') {
            throw "Private compressed evidence retrieval failed: $message"
        }
        Write-Warning "Private evidence transfer encountered a transient connection failure ($attempt/3); retrying the same completed archive: $message"
        Start-Sleep -Seconds 5
    }
    & tar -xzf $archive -C $evidenceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Private evidence archive extraction failed.' }
}

function Test-LabDurability {
    param([string] $ManifestPath, [string] $RunId, [int] $TunnelPort,
        [ValidateSet('warmup', 'baseline', 'app-instance', 'app-zone', 'failover', 'combined')][string] $Phase)
    if ($RunId -notmatch '^[0-9a-f]{32}$') { throw 'Invalid durability run ID.' }
    $manifest = Read-LabManifest $ManifestPath
    $root = Split-Path $ManifestPath -Parent
    $options = @(Get-LabSshOptions $manifest $root)
    Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Verifying original $Phase writes through the private API." -InformationAction Continue
    & ssh @options -p $TunnelPort 'csloperator@127.0.0.1' "cd ~/csl && timeout 1200 pwsh -NoLogo -NoProfile -File scripts/runner/verify.ps1 -AcknowledgedAttemptsPath results/$RunId/attempts.ndjson > $Phase-durability.log 2>&1"
    $verificationExit = $LASTEXITCODE
    $report = Join-Path $root "evidence\$Phase-durability-verdict.json"
    & scp @options -P $TunnelPort "csloperator@127.0.0.1:csl/results/$RunId/durability-verdict.json" $report
    if ($LASTEXITCODE -ne 0) { throw 'Private durability evidence retrieval failed.' }
    $verdict = Get-Content $report -Raw | ConvertFrom-Json
    if ($verificationExit -ne 0 -or $verdict.status -ne 'PASS' -or $verdict.lostAcknowledgedWrites -ne 0) {
        throw "Private $Phase durability verification failed; inspect its saved verdict and runner log."
    }
    Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Durability passed: $($verdict.issuedUniqueWrites) unique writes reconciled; no acknowledged loss." -InformationAction Continue
}

function Wait-LabSsh {
    param([hashtable] $Manifest, [string] $StateRoot, [int] $TunnelPort)
    $options = @(Get-LabSshOptions $Manifest $StateRoot)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $probe = & ssh @options -p $TunnelPort 'csloperator@127.0.0.1' true 2>&1
        if ($LASTEXITCODE -eq 0) { return }
        $message = $probe -join [Environment]::NewLine
        if ($message -match 'Permission denied|Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED|Bad configuration option' -or
            $attempt -eq 6) {
            throw "Private SSH readiness failed: $message"
        }
        Write-Warning "Bastion listener is reachable but authenticated SSH is not ready ($attempt/6): $message"
        Start-Sleep 5
    }
}

function Confirm-LabContext {
    $account = Invoke-LabAz @('account', 'show', '-o', 'json') | ConvertFrom-Json
    if ($account.id -ne $script:LabSubscription -or $account.tenantId -ne $script:LabTenant) {
        throw 'CLI subscription or tenant differs from the authorized lab context.'
    }
    if ($account.user.name -ne $script:LabEnvironment.expectedAccount) {
        throw 'CLI identity differs from the locally approved identity. No login or PIM change was attempted.'
    }
}

function Invoke-LabArm {
    param([ValidateSet('Get','Post','Put')][string] $Method, [string] $Uri, [object] $Body = $null)
    $address = [Uri] $Uri
    if (-not $address.IsAbsoluteUri -or $address.Scheme -ne 'https' -or
        $address.Host -ne 'management.azure.com' -or $address.Port -ne 443 -or
        $address.UserInfo -or $address.Fragment) { throw 'Unexpected management API address.' }
    Assert-LabResourceId $address.AbsolutePath
    $accessToken = Invoke-LabAz @('account', 'get-access-token', '--resource', 'https://management.azure.com/', '--query', 'accessToken', '-o', 'tsv')
    try {
        $arguments = @{
            Uri = $Uri; Method = $Method; Headers = @{ Authorization = "Bearer $accessToken" }
            TimeoutSec = 120; ContentType = 'application/json'; MaximumRedirection = 0
        }
        if ($null -ne $Body) { $arguments.Body = $Body | ConvertTo-Json -Depth 50 }
        $response = Invoke-WebRequest @arguments
        return @{
            statusCode = $response.StatusCode
            headers = $response.Headers
            body = if ($response.Content) { $response.Content | ConvertFrom-Json -AsHashtable } else { $null }
        }
    } finally { $accessToken = $null }
}

function Write-LabJson {
    param([string] $Path, [object] $Value)
    $temporary = "$Path.tmp"
    ConvertTo-Json -InputObject $Value -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Assert-LabBuildValidation {
    param([string] $Step, [string] $Plan)
    if ($Plan -notmatch 'Status:\*\* (Validated|Deployed)\b') {
        throw 'The deployment plan must be Validated by azure-validate before cloud provisioning.'
    }
    if ($Plan -notmatch '\*\*Validated build steps:\*\* (?<steps>[^\r\n]+)' -or
        $Step -notin @($Matches.steps.Split(',').Trim())) {
        throw "The deployment plan is not yet validated for the $Step build step."
    }
}

function Export-LabIdentityTemplate {
    param([string] $ModulePath, [string] $OutputPath)
    $source = Invoke-LabAz @('bicep', 'build', '--file', $ModulePath, '--stdout') |
        ConvertFrom-Json -AsHashtable
    $identities = @($source.resources | Where-Object type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities')
    if ($identities.Count -eq 0 -or @($identities | Where-Object { $_.ContainsKey('dependsOn') }).Count) {
        throw 'Identity prerequisites must be independent source resources.'
    }
    Write-LabJson $OutputPath @{
        '$schema' = $source['$schema']; contentVersion = $source.contentVersion
        parameters = @{
            location = $source.parameters.location
            deploymentInstanceId = $source.parameters.deploymentInstanceId
        }
        variables = @{ labTags = $source.variables.labTags }
        resources = $identities
    }
}

function Get-LabPrerequisitePrincipalIds {
    param([hashtable] $Manifest)
    $identities = @(
        foreach ($index in @(1, 2)) {
            Invoke-LabAz @('identity', 'list', '-g', $script:LabGroups[$index], '-o', 'json') |
                ConvertFrom-Json -AsHashtable
        }
    )
    $result = @{}
    foreach ($entry in @(
        @{key = 'migration'; index = 1; name = 'id-csl-migrations'}
        @{key = 'runner'; index = 2; name = 'id-csl-runner'}
        @{key = 'chaos'; index = 1; name = 'id-csl-chaos'}
        @{key = 'runtime'; index = 1; name = 'id-csl-runtime'}
    )) {
        $id = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[$entry.index])/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$($entry.name)"
        $matches = @($identities | Where-Object id -IEQ $id)
        $principal = [Guid]::Empty
        if ($matches.Count -ne 1 -or $null -eq $matches[0]['tags'] -or
            $matches[0].tags['deploymentInstanceId'] -ne $Manifest.deploymentInstanceId -or
            -not [Guid]::TryParse($matches[0]['principalId'], [ref]$principal) -or $principal -eq [Guid]::Empty -or
            $id -notin $Manifest.resourceIds) {
            throw "Missing or foreign prerequisite identity: $($entry.name). Complete the owned Prerequisites step before full validation."
        }
        if ($entry.key) { $result[$entry.key] = $principal.ToString() }
    }
    return $result
}

function Assert-LabRegionalCapabilities {
    $capabilities = Invoke-LabAz @('rest', '--method', 'get', '--url',
        "https://management.azure.com/subscriptions/$script:LabSubscription/providers/Microsoft.DBforPostgreSQL/locations/$script:LabLocation/capabilities?api-version=2024-08-01",
        '-o', 'json') | ConvertFrom-Json -AsHashtable
    $entries = @($capabilities.value)
    if ($entries.Count -ne 1 -or $entries[0]['restricted'] -ne 'Disabled' -or
        $entries[0]['zoneRedundantHaSupported'] -ne 'Enabled') {
        throw "BLOCKED: PostgreSQL subscription-level zoneRedundantHaSupported is not Enabled in $script:LabLocation. Per-SKU supportedHaMode alone is insufficient. Select a verified compatible lab region or request eligibility through Azure portal > Help + support > Service and subscription limits before creating resources."
    }
}

function Assert-LabLinuxRuntime {
    param([object[]] $Runtimes)
    $qualified = @($Runtimes | Where-Object {
        $_ -is [hashtable] -and $_.ContainsKey('config') -and $_.config -eq 'DOTNETCORE|9.0' -and
        $_.ContainsKey('os') -and $_.os -eq 'Linux' -and
        $_.ContainsKey('support') -and $_.support -in @('Active', 'Near')
    })
    if ($qualified.Count -ne 1) {
        throw 'BLOCKED: the qualified Linux DOTNETCORE|9.0 runtime is missing, unsupported or ambiguous.'
    }
    $runtime = $qualified[0]
    $endOfLife = [DateTimeOffset]::MinValue
    if (-not $runtime.ContainsKey('end_of_life') -or
        -not [DateTimeOffset]::TryParse($runtime.end_of_life, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$endOfLife) -or
        $endOfLife -le [DateTimeOffset]::UtcNow) {
        throw 'BLOCKED: the qualified Linux runtime needs a verified future catalog end_of_life date.'
    }
    if ($runtime.support -eq 'Near') {
        Write-Warning "Bounded lab runtime DOTNETCORE|9.0 is Near end of support ($($runtime.end_of_life)); requalify a supported native-compatible runtime before that date."
    }
}

function Assert-LabAppServicePlan {
    param([hashtable] $Plan)
    if ('linux' -notin @($Plan.kind -split ',') -or
        $Plan.properties.reserved -ne $true -or
        $Plan.properties.zoneRedundant -ne $true -or
        $Plan.properties.perSiteScaling -ne $false -or
        $Plan.sku.capacity -ne 6 -or
        -not $Plan.properties.ContainsKey('maximumNumberOfZones') -or
        $Plan.properties.maximumNumberOfZones -lt 3) {
        throw 'BLOCKED: the actual plan must be Linux, zoneRedundant=true, maximumNumberOfZones>=3, capacity=6 and perSiteScaling=false to qualify the requested baseline.'
    }
}

function Assert-LabAppServiceConfiguration {
    param([hashtable] $Configuration)
    if (-not $Configuration.ContainsKey('alwaysOn') -or
        $Configuration.alwaysOn -isnot [bool] -or $Configuration.alwaysOn -ne $true) {
        throw 'BLOCKED: actual App Service config/web must have alwaysOn=true to retain the six-worker baseline during idle periods.'
    }
    if (-not $Configuration.ContainsKey('linuxFxVersion') -or $Configuration.linuxFxVersion -cne 'DOTNETCORE|9.0') {
        throw 'BLOCKED: actual App Service config/web must use the native-qualified Linux DOTNETCORE|9.0 runtime.'
    }
}

function Assert-LabAppServicePlacement {
    param([hashtable] $Plan, [object[]] $Instances, [object[]] $Observations)
    Assert-LabAppServicePlan $Plan
    if ($Instances.Count -ne 6 -or @($Instances.name | Sort-Object -Unique).Count -ne 6) {
        throw 'BLOCKED: exactly six distinct actual application instances are required.'
    }
    $zones = @()
    foreach ($instance in $Instances) {
        if ([string]::IsNullOrWhiteSpace($instance.name) -or
            [string]::IsNullOrWhiteSpace($instance.properties.physicalZone)) {
            throw 'BLOCKED: every actual application instance needs an ID and physicalZone.'
        }
        $zones += $instance.properties.physicalZone
        $health = @($Observations | Where-Object {
            $_.instanceId -eq $instance.name -and $_.status -eq 'live'
        })
        $traffic = @($Observations | Where-Object {
            $_.instanceId -eq $instance.name -and $_.businessSuccess -eq $true
        })
        if ($health.Count -eq 0 -or $traffic.Count -eq 0) {
            throw "BLOCKED: missing actual health/business participation for instance $($instance.name)."
        }
    }
    if (@($zones | Sort-Object -Unique).Count -ne 3) {
        throw 'BLOCKED: healthy application traffic must represent exactly three distinct observed physicalZone values.'
    }
}

function Assert-LabPolicyExemptions {
    [CmdletBinding()]
    param([hashtable] $Manifest)
    $required = @()
    if ($script:LabEnvironment.ContainsKey('requiredPolicyExemptions')) {
        $required += @($script:LabEnvironment.requiredPolicyExemptions)
    }
    if ($null -ne $Manifest -and $Manifest.ContainsKey('policyExemptions')) {
        $required += @($Manifest.policyExemptions)
    }
    foreach ($expected in $required) {
        if ($null -eq $expected -or -not $expected.ContainsKey('id') -or
            -not $expected.ContainsKey('assignmentId') -or -not $expected.assignmentId -or
            -not $expected.ContainsKey('referenceIds') -or @($expected.referenceIds).Count -ne 1) {
            throw 'Invalid requiredPolicyExemptions entry: supply id, assignmentId and one referenceIds value in the private environment file or manifest.'
        }
        Assert-LabResourceId $expected.id
        if ($expected.id -notmatch '^(?<scope>.+/resourceGroups/(?<group>[^/]+))/providers/Microsoft.Authorization/policyExemptions/(?<name>[^/]+)$') {
            throw 'Required policy exemption must be scoped to an exact lab resource group.'
        }
        $scope = $Matches.scope
        $group = $Matches.group
        $name = $Matches.name
        $guidance = "BLOCKED: required policy exemption '$name' in resource group '$group' needs repair. Create the scoped exemption or extend expiresOn (Azure portal: Policy > Exemptions), preserving policyAssignmentId, policyDefinitionReferenceIds and the public-IP selector. Record it in '$script:LabEnvironmentPath' requiredPolicyExemptions and the owned manifest, then rerun validation."
        if ((Invoke-LabAz @('group', 'exists', '-n', $group, '-o', 'tsv')) -ne 'true') {
            throw "$guidance The group/exemption is missing; prepare a new owned scope before creating the exemption."
        }
        $records = @(Invoke-LabAz @('policy', 'exemption', 'list', '--scope', $scope,
            '--disable-scope-strict-match', 'false', '-o', 'json') | ConvertFrom-Json -AsHashtable)
        $matching = @($records | Where-Object id -IEQ $expected.id)
        if ($matching.Count -ne 1) { throw "$guidance The exemption is missing." }
        $actual = $matching[0]
        foreach ($key in @('expiresOn', 'policyAssignmentId', 'policyDefinitionReferenceIds', 'exemptionCategory', 'resourceSelectors')) {
            if (-not $actual.ContainsKey($key) -or $null -eq $actual[$key]) {
                throw "$guidance The live exemption is missing required property $key."
            }
        }
        $expires = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($actual.expiresOn, [ref]$expires)) {
            throw "$guidance A finite expiry is required."
        }
        if ($expires -le [DateTimeOffset]::UtcNow) {
            throw "$guidance EXPIRED at $($expires.ToUniversalTime().ToString('O'))."
        }
        if ($actual.policyAssignmentId -ine $expected.assignmentId -or
            @($actual.policyDefinitionReferenceIds).Count -ne 1 -or
            @($expected.referenceIds).Count -ne 1 -or
            $actual.policyDefinitionReferenceIds[0] -ne $expected.referenceIds[0] -or
            $actual.exemptionCategory -ne 'Waiver' -or
            @($actual.resourceSelectors).Count -ne 1 -or
            @($actual.resourceSelectors[0].selectors).Count -ne 1 -or
            $actual.resourceSelectors[0].selectors[0].kind -ne 'resourceType' -or
            @($actual.resourceSelectors[0].selectors[0]['in']).Count -ne 1 -or
            $actual.resourceSelectors[0].selectors[0]['in'][0] -ne 'Microsoft.Network/publicIPAddresses') {
            throw "$guidance Live exemption scope/reference/category/selector differs from the approved contract."
        }
        if ($expires -lt [DateTimeOffset]::UtcNow.AddHours(2)) {
            Write-Warning "Policy exemption '$name' expires at $($expires.ToUniversalTime().ToString('O')), within two hours. Extend expiresOn and verify the live exemption before a longer measurement."
        }
    }
}

function Read-LabManifest {
    param([string] $Path)
    $m = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($m.schemaVersion -ne 1 -or $m.subscriptionId -ne $script:LabSubscription -or
        $m.tenantId -ne $script:LabTenant -or $m.labId -ne 'lab-dev01' -or
        $m.deploymentInstanceId -notmatch '^[0-9a-f]{32}$') {
        throw 'Invalid or foreign ownership manifest.'
    }
    $names = @($m.groups | ForEach-Object { $_.name })
    if ($names.Count -ne 3 -or @($script:LabGroups | Where-Object { $_ -notin $names }).Count -gt 0) {
        throw 'Manifest does not contain exactly the authorized three groups.'
    }
    foreach ($group in $m.groups) {
        $expected = "/subscriptions/$script:LabSubscription/resourceGroups/$($group.name)"
        if ($group.id -ine $expected) { throw 'Manifest resource group ID mismatch.' }
    }
    foreach ($id in $m.resourceIds) { Assert-LabResourceId $id }
    return $m
}

function Assert-LabResourceId {
    param([string] $Id)
    foreach ($group in $script:LabGroups) {
        $prefix = "/subscriptions/$script:LabSubscription/resourceGroups/$group/providers/"
        if ($Id.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    throw "Resource is outside the authorized lab groups: $Id"
}

function Get-LabInventory {
    param([hashtable] $Manifest)
    $ids = [System.Collections.Generic.List[string]]::new()
    $existingGroups = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $Manifest.groups) {
        $exists = Invoke-LabAz @('group', 'exists', '-n', $group.name, '-o', 'tsv')
        if ($exists -eq 'false') { continue }
        $actual = Invoke-LabAz @('group', 'show', '-n', $group.name, '-o', 'json') | ConvertFrom-Json -AsHashtable
        if ($actual.tags.deploymentInstanceId -ne $Manifest.deploymentInstanceId -or
            $actual.tags.labId -ne $Manifest.labId) { throw "Foreign group ownership: $($group.name)" }
        [void]$existingGroups.Add($group.name)
        $resources = Invoke-LabAz @('resource', 'list', '-g', $group.name, '-o', 'json') | ConvertFrom-Json -AsHashtable
        foreach ($resource in $resources) {
            Assert-LabResourceId $resource.id
            if ($resource.ContainsKey('tags') -and $null -ne $resource.tags -and
                $resource.tags.ContainsKey('deploymentInstanceId') -and
                $resource.tags.deploymentInstanceId -ne $Manifest.deploymentInstanceId) {
                throw "Foreign deployment resource in the lab group: $($resource.id)"
            }
            $ids.Add($resource.id)
        }
        $exemptions = Invoke-LabAz @('policy', 'exemption', 'list', '--scope', $group.id,
            '--disable-scope-strict-match', 'false', '-o', 'json') | ConvertFrom-Json -AsHashtable
        foreach ($exemption in $exemptions) {
            Assert-LabResourceId $exemption.id
            $ids.Add($exemption.id)
        }
    }
    if ($Manifest.ContainsKey('deploymentRoots')) {
        $queue = [Collections.Generic.Queue[object]]::new()
        $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($root in $Manifest.deploymentRoots) { $queue.Enqueue($root) }
        while ($queue.Count -gt 0) {
            $deployment = $queue.Dequeue()
            if ($deployment.group -notin $script:LabGroups) { throw 'Foreign deployment inventory scope.' }
            if (-not $visited.Add("$($deployment.group)/$($deployment.name)")) { continue }
            if (-not $existingGroups.Contains($deployment.group)) { continue }
            $operations = Invoke-LabAz @('deployment', 'operation', 'group', 'list', '-g', $deployment.group,
                '-n', $deployment.name, '-o', 'json') | ConvertFrom-Json -AsHashtable
            foreach ($operation in $operations) {
                $properties = $operation.properties
                if (-not $properties.ContainsKey('targetResource') -or $null -eq $properties.targetResource) { continue }
                $target = $properties.targetResource
                Assert-LabResourceId $target.id
                if ($target.resourceType -eq 'Microsoft.Resources/deployments') {
                    if ($properties.provisioningState -in @('Succeeded', 'Failed')) {
                        $queue.Enqueue(@{ group = ($target.id -split '/')[4]; name = $target.resourceName })
                    }
                } elseif ($properties.provisioningState -eq 'Succeeded') {
                    $ids.Add($target.id)
                }
            }
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Save-LabInventory {
    param([hashtable] $Manifest, [string] $Path)
    $Manifest.resourceIds = @(Get-LabInventory $Manifest)
    $Manifest.updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    Write-LabJson $Path $Manifest
}

function Assert-LabDestroyInventory {
    param([hashtable] $Manifest, [string[]] $ActualIds)
    foreach ($id in $ActualIds) {
        Assert-LabResourceId $id
        if ($id -notin $Manifest.resourceIds) {
            throw "Unrecorded resource prevents group destruction: $id"
        }
    }
}

function Assert-LabPublicIpChanges {
    param([object[]] $Changes)
    foreach ($change in $Changes) {
        if ($change.changeType -notin @('Create', 'Modify', 'Deploy')) { continue }
        if ($change.resourceId -notmatch '/providers/Microsoft.Network/publicIPAddresses/[^/]+$') { continue }
        if (-not $change.ContainsKey('after') -or $null -eq $change.after) {
            throw "Cannot verify the effective public-IP payload: $($change.resourceId)"
        }
        $after = $change.after
        if (-not $after.ContainsKey('properties') -or $null -eq $after.properties -or
            -not $after.ContainsKey('sku') -or $null -eq $after.sku -or
            -not $after.sku.ContainsKey('name') -or $after.sku.name -ne 'Standard') {
            throw "The NAT/Bastion public IP requires the Standard SKU: $($change.resourceId)"
        }
        $properties = $after.properties
        if (-not $properties.ContainsKey('publicIPAllocationMethod') -or $properties.publicIPAllocationMethod -ne 'Static' -or
            -not $properties.ContainsKey('publicIPAddressVersion') -or $properties.publicIPAddressVersion -ne 'IPv4') {
            throw "Public IP must use Azure-allocated static IPv4: $($change.resourceId)"
        }
    }
}

function Initialize-LabMachines {
    param([string] $ManifestPath, [IO.FileStream] $ManifestLock)
    Confirm-LabContext
    Assert-LabPolicyExemptions (Read-LabManifest $ManifestPath)
    Assert-LabBuildValidation 'Runner' (Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw)
    if ($null -eq $ManifestLock -or -not $ManifestLock.CanWrite -or
        $ManifestLock.Name -ine [IO.Path]::GetFullPath("$ManifestPath.lock")) {
        throw 'Runner initialization requires the caller-held exclusive manifest lock.'
    }
    $manifest = Read-LabManifest $ManifestPath
    try {
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Installing the single owned runner in the foreground; guest deadline 20 minutes." -InformationAction Continue
        $vm = Invoke-LabAz @('vm', 'show', '-g', $script:LabGroups[2], '-n', 'vm-csl-runner', '-o', 'json') |
            ConvertFrom-Json -AsHashtable
        Assert-LabResourceId $vm.id
        if ($vm.id -notin $manifest.resourceIds -or $vm.tags.deploymentInstanceId -ne $manifest.deploymentInstanceId -or
            $vm.tags.labId -ne $manifest.labId) { throw 'Missing or foreign installation target: vm-csl-runner' }
        $installStarted = [DateTimeOffset]::UtcNow
        $source = [IO.File]::ReadAllText((Join-Path $script:LabRoot 'scripts\runner\install.sh')).Replace("`r`n", "`n")
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
        $install = Invoke-LabAz @('vm', 'run-command', 'invoke', '-g', $script:LabGroups[2], '-n', 'vm-csl-runner',
            '--command-id', 'RunShellScript', '--scripts',
            "printf '%s' '$encoded' | base64 -d > /tmp/csl-install.sh && timeout 1200 bash /tmp/csl-install.sh", '-o', 'json') |
            ConvertFrom-Json -AsHashtable
        $install.startedAtUtc = $installStarted.ToString('O')
        $install.completedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        Write-LabJson (Join-Path (Split-Path $ManifestPath -Parent) 'vm-csl-runner-install.json') $install
        if (($install.value.message -join "`n") -notmatch '(?m)^CSL_INSTALL_COMPLETED\r?$') {
            throw 'Runner software installation did not reach its final success marker. Inspect the saved install JSON before retrying.'
        }
        Write-Information 'Single-runner software checks passed.' -InformationAction Continue
    } finally {
        Save-LabInventory $manifest $ManifestPath
    }
}

function Invoke-LabDeployment {
    param(
        [hashtable] $Manifest, [string] $ManifestPath, [string] $Group,
        [string] $Name, [string] $Template, [hashtable] $Parameters
    )
    if ($Group -notin $script:LabGroups) { throw 'Deployment group is outside the authorized boundary.' }
    Assert-LabPolicyExemptions $Manifest
    $stateRoot = Split-Path $ManifestPath -Parent
    $parameterPath = Join-Path $stateRoot "$Name.parameters.json"
    $armParameters = @{}
    foreach ($entry in $Parameters.GetEnumerator()) { $armParameters[$entry.Key] = @{ value = $entry.Value } }
    Write-LabJson $parameterPath @{ parameters = $armParameters }
    try {
        $stageStarted = [DateTimeOffset]::UtcNow
        Write-Information "[$($stageStarted.ToString('O'))] Previewing $Name in $Group." -InformationAction Continue
        $whatIf = Invoke-LabAz @('deployment', 'group', 'what-if', '-g', $Group, '-n', $Name,
            '--template-file', $Template, '--parameters', "@$parameterPath",
            '--result-format', 'FullResourcePayloads', '--no-pretty-print', '-o', 'json') | ConvertFrom-Json -AsHashtable
        Write-LabJson (Join-Path $stateRoot "$Name.what-if.json") $whatIf
        if ($whatIf.status -ne 'Succeeded' -or
            ($whatIf.ContainsKey('error') -and $null -ne $whatIf.error)) { throw "What-if failed for $Name" }
        if (($whatIf.ContainsKey('diagnostics') -and $null -ne $whatIf.diagnostics -and @($whatIf.diagnostics | Where-Object {
                $_.level -in @('Warning', 'Error')
            }).Count -gt 0) -or
            ($whatIf.ContainsKey('potentialChanges') -and $null -ne $whatIf.potentialChanges -and
                @($whatIf.potentialChanges).Count -gt 0)) {
            throw "Incomplete effective preview for $Name. Resolve provider diagnostics, skipped nested deployments and potential changes before provisioning."
        }
        foreach ($change in $whatIf.changes) {
            Assert-LabResourceId $change.resourceId
            if ($change.changeType -eq 'Delete' -and $change.resourceId -notin $Manifest.resourceIds) {
                throw "What-if proposes deletion of an unrecorded resource: $($change.resourceId)"
            }
            if ($change.changeType -notin @('Create', 'Modify', 'Deploy', 'Delete', 'NoChange', 'Ignore')) {
                throw "What-if could not evaluate the resource change: $($change.resourceId)"
            }
            if ($change.changeType -in @('Modify', 'Deploy', 'Delete') -and
                $change.resourceId -notin $Manifest.resourceIds -and
                $change.resourceId -notmatch '/Microsoft.Resources/deployments/') {
                throw "What-if proposes a change to an unowned resource: $($change.resourceId)"
            }
        }
        Assert-LabPublicIpChanges $whatIf.changes
        if (-not $Manifest.ContainsKey('deploymentRoots')) { $Manifest.deploymentRoots = @() }
        if (@($Manifest.deploymentRoots | Where-Object { $_.group -eq $Group -and $_.name -eq $Name }).Count -eq 0) {
            $Manifest.deploymentRoots += @{ group = $Group; name = $Name }
        }
        Write-LabJson $ManifestPath $Manifest
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Deploying $Name; provider provisioning may take several minutes." -InformationAction Continue
        $result = Invoke-LabAz @('deployment', 'group', 'create', '-g', $Group, '-n', $Name,
            '--template-file', $Template, '--parameters', "@$parameterPath", '-o', 'json') |
            ConvertFrom-Json -AsHashtable
        Write-LabJson (Join-Path $stateRoot "$Name.deployment.json") $result
        $Manifest.outputs[$Name] = $result.properties.outputs
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] $Name completed in $([Math]::Round(([DateTimeOffset]::UtcNow - $stageStarted).TotalSeconds)) seconds." -InformationAction Continue
        return $result.properties.outputs
    } finally {
        Remove-Item -LiteralPath $parameterPath -ErrorAction SilentlyContinue
        Save-LabInventory $Manifest $ManifestPath
    }
}
