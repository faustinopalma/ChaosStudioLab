function Get-LabNativePollUri {
    param([hashtable] $Response)
    $uri=[string]($Response.headers['Location'] | Select-Object -First 1)
    if([string]::IsNullOrWhiteSpace($uri)) {
        if($null -eq $Response.body -or -not $Response.body.ContainsKey('id')) {
            throw 'Native operation acceptance has no Location or resource ID.'
        }
        $uri="https://management.azure.com$($Response.body.id)?api-version=2026-08-01-preview"
    }
    $address=[Uri]$uri
    if(-not $address.IsAbsoluteUri -or $address.Scheme -ne 'https' -or
        $address.Host -ne 'management.azure.com' -or $address.Port -ne 443 -or
        $address.UserInfo -or $address.Fragment) { throw 'Unexpected native operation polling address.' }
    Assert-LabResourceId $address.AbsolutePath
    return $uri
}

function Wait-LabNativeOperation {
    param(
        [string] $PollUri, [string] $EvidencePrefix,
        [ValidateRange(1,900)][int] $TimeoutSeconds=900,
        [switch] $AllowFailedTerminal,
        [ValidateSet('Execution','Validation')][string] $OperationKind='Execution'
    )
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $index=0
    do {
        $response=Invoke-LabArm Get $PollUri
        Write-LabJson "$EvidencePrefix-poll-$($index.ToString('D3')).json" $response
        $index++
        if($response.statusCode -eq 200) {
            if($null -eq $response.body -or -not $response.body.ContainsKey('properties') -or
                -not $response.body.properties.ContainsKey('status')) {
                throw 'Native terminal operation is missing its explicit status.'
            }
            $status=$response.body.properties.status
            if($status -eq 'Succeeded') { return $response.body }
            if($status -in @('Failed','Canceled','Cancelled') -or
                ($OperationKind -eq 'Validation' -and $status -eq 'RequiresAttention')) {
                if($AllowFailedTerminal) { return $response.body }
                throw "Native operation ended as $($response.body.properties.status): $($response.body.properties | ConvertTo-Json -Depth 30 -Compress)"
            }
            if($status -notin @('Running','Accepted','Queued','InProgress')) { throw "Unknown native operation status: $status." }
        }
        if($response.statusCode -notin @(200,202)) { throw "Unexpected native operation HTTP $($response.statusCode)." }
        if([DateTimeOffset]::UtcNow -lt $deadline) { Start-Sleep -Seconds 5 }
    } while([DateTimeOffset]::UtcNow -lt $deadline)
    throw 'Native operation exceeded its bounded foreground deadline; retain its polling URL and reconcile in place.'
}

function Confirm-LabNativeValidation {
    param([string] $ConfigurationId,[string] $TargetId,[string] $EvidencePrefix)
    Assert-LabResourceId $ConfigurationId
    Assert-LabResourceId $TargetId
    $acceptance=Invoke-LabArm Post "https://management.azure.com$ConfigurationId/validate?api-version=2026-08-01-preview"
    Write-LabJson "$EvidencePrefix-acceptance.json" $acceptance
    if($acceptance.statusCode -notin @(200,202)) { throw "Native validation returned HTTP $($acceptance.statusCode)." }
    $result=Wait-LabNativeOperation (Get-LabNativePollUri $acceptance) $EvidencePrefix -TimeoutSeconds 300 `
        -AllowFailedTerminal -OperationKind Validation
    Write-LabJson "$EvidencePrefix-terminal.json" $result
    $properties=$result.properties
    $validationErrors=if($properties.ContainsKey('validationErrors')) { $properties.validationErrors } else { $null }
    if($properties.status -ne 'Succeeded') {
        $diagnostics=@{errors=$properties.errors;validationErrors=$validationErrors} | ConvertTo-Json -Depth 15 -Compress
        throw "BLOCKED: native non-fault validation ended as $($properties.status): $diagnostics"
    }
    if(@($properties.resources).Count -ne 1 -or $properties.resources[0].id -ine $TargetId -or
        @($properties.errors | Where-Object { $null -ne $_ }).Count -gt 0 -or
        ($null -ne $validationErrors -and
            (@($validationErrors.permission).Count -gt 0 -or @($validationErrors.resource).Count -gt 0))) {
        throw 'BLOCKED: native validation lacks clean evidence for the exact owned target.'
    }
    Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Native non-fault validation passed for the exact owned target." -InformationAction Continue
    return $result
}

function Get-LabNativeActionUrn {
    param([string] $ActionId)
    switch -CaseSensitive ($ActionId) {
        'microsoft-appservice-killprocess/1.0' { return 'urn:csci:microsoft:appservice:killprocess/1.0.0' }
        'urn:csci:microsoft:appservice:killprocess/1.0.0' { return $ActionId }
        'microsoft-azurepostgresql-failover/1.0' { return 'urn:csci:microsoft:azurepostgresql:failover/1.0.0' }
        'urn:csci:microsoft:azurepostgresql:failover/1.0.0' { return $ActionId }
        default { throw "Unqualified native Action identifier: $ActionId" }
    }
}

function Complete-LabNativeExecution {
    param([hashtable] $Intent,[hashtable] $Manifest,[string] $ManifestPath,[string] $EvidencePrefix,
        [hashtable] $Scenario,[string] $TargetId,[string] $PrincipalId)
    $result=Wait-LabNativeOperation $Intent.pollUri $EvidencePrefix -AllowFailedTerminal
    Write-LabJson "$EvidencePrefix-terminal.json" $result
    $Intent.status=if($result.properties.status -eq 'Succeeded') { 'TERMINAL_UNVERIFIED' } else { 'FAILED_RECONCILED' }
    $Intent.terminalStatus=$result.properties.status
    $Intent.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
    $Intent.terminalEvidencePath="$EvidencePrefix-terminal.json"
    Write-LabJson $ManifestPath $Manifest
    if($result.properties.status -ne 'Succeeded') {
        Write-Warning "[$($Intent.finishedAtUtc)] Native execution ended as $($result.properties.status); exact provider errors are saved in $EvidencePrefix-terminal.json. The operation is reconciled; bounded measurement and write retention still complete."
        return $result
    }
    if($result.properties.managedIdentityPrincipalId -ine $PrincipalId -or
        @($result.properties.resources).Count -ne 1 -or $result.properties.resources[0].id -ine $TargetId) {
        throw 'Native execution identity or actual target differs from the verified owned configuration.'
    }
    $compiled=$result.properties.scenarioRunJson | ConvertFrom-Json -AsHashtable
    if($compiled.actions.Count -ne 1) { throw 'Native execution compiled an unexpected Action count.' }
    $actual=@($compiled.actions.Values)[0].properties
    $expected=@($Scenario.properties.actions)[0]
    if($actual.faultUrn -cne (Get-LabNativeActionUrn $expected.actionId) -or @($actual.targetResources).Count -ne 1 -or
        $actual.targetResources[0].fullyQualifiedIdentifier -ine $TargetId -or
        $actual.faultParameters.Count -ne @($expected.parameters).Count) { throw 'Native compiled Action or target contract drifted.' }
    foreach($parameter in $expected.parameters) {
        if($actual.faultParameters[$parameter.key] -cne $parameter.value) { throw "Native compiled parameter $($parameter.key) differs from its explicit definition." }
    }
    if(@($result.properties.errors | Where-Object { $null -ne $_ }).Count -gt 0 -or @($result.properties.scenarioRunSummary).Count -ne 1 -or
        $result.properties.scenarioRunSummary[0].state -ne 'Succeeded') { throw 'Native execution lacks clean successful Action-level evidence.' }
    $Intent.status='SUCCEEDED'
    Write-LabJson $ManifestPath $Manifest
    return $result
}

function Find-LabNativeTargets {
    param([string] $WorkspaceId,[string[]] $TargetIds,[string] $EvidenceRoot)
    $workspace=Invoke-LabArm Get "https://management.azure.com${WorkspaceId}?api-version=2026-08-01-preview"
    Write-LabJson (Join-Path $EvidenceRoot 'workspace.json') $workspace
    $scope="/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])"
    if(@($workspace.body.properties.scopes).Count -ne 1 -or $workspace.body.properties.scopes[0] -ine $scope) {
        throw 'Native Workspace discovery scope differs from the exact owned workload group.'
    }
    $response=Invoke-LabArm Post "https://management.azure.com$WorkspaceId/discover?api-version=2026-08-01-preview"
    Write-LabJson (Join-Path $EvidenceRoot 'discovery-acceptance.json') $response
    Wait-LabNativeOperation (Get-LabNativePollUri $response) (Join-Path $EvidenceRoot 'discovery') | Out-Null
    $pageUri="https://management.azure.com$WorkspaceId/discoveredResources?api-version=2026-08-01-preview"
    $targets=[Collections.Generic.List[object]]::new()
    for($pageNumber=0;$pageUri -and $pageNumber -lt 20;$pageNumber++) {
        $page=Invoke-LabArm Get $pageUri
        Write-LabJson (Join-Path $EvidenceRoot "discovered-resources-$pageNumber.json") $page
        foreach($resource in $page.body.value) {
            if($resource.properties.fullyQualifiedIdentifier -in $TargetIds) { $targets.Add($resource) }
        }
        $pageUri=if($page.body.ContainsKey('nextLink')) { $page.body.nextLink } else { $null }
    }
    if($pageUri) { throw 'Owned native discovery exceeded its bounded twenty-page limit.' }
    foreach($id in $TargetIds) {
        if(@($targets | Where-Object { $_.properties.fullyQualifiedIdentifier -ieq $id }).Count -ne 1) {
            throw "BLOCKED: native discovery did not expose exactly one owned target: $id"
        }
    }
    return $targets.ToArray()
}

function Get-LabNativeScenarioId {
    param([hashtable] $Configuration)
    $configurationId=[string]$Configuration.id
    Assert-LabResourceId $configurationId
    if($configurationId -notmatch '^(?<parent>/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Chaos/workspaces/[^/]+/scenarios/(?<name>[^/]+))/configurations/[^/]+$') {
        throw 'Native configuration has an invalid Scenario parent resource ID.'
    }
    $parent=$Matches.parent
    $name=$Matches.name
    $binding=[string]$Configuration.properties.scenarioId
    if($binding -ine $parent -and $binding -ine $name) {
        throw 'Native configuration Scenario binding differs from its owned parent resource.'
    }
    return $parent
}

function Assert-LabNativeConfiguration {
    param([hashtable] $Configuration,[hashtable] $Scenario,[string] $TargetId,
        [ValidateSet('instance','zone','postgres')][string] $Kind,[string] $Selector)
    $targets=@($Configuration.properties.resourceTargeting.include.resources)
    if($targets.Count -ne 1 -or $targets[0] -ine $TargetId -or
        (Get-LabNativeScenarioId $Configuration) -ine $Scenario.id) {
        throw 'Native configuration does not bind the exact intended Scenario and single owned resource.'
    }
    $actions=@($Scenario.properties.actions)
    if($actions.Count -ne 1) { throw 'Expected exactly one explicitly configured native Action.' }
    $actionUrn=Get-LabNativeActionUrn $actions[0].actionId
    $parameters=@{}
    foreach($parameter in $actions[0].parameters) {
        if($parameters.ContainsKey($parameter.key)) { throw 'Duplicate native Action parameter.' }
        if($parameter.value -isnot [string]) { throw 'Native Action parameter values must use the provider string contract.' }
        $parameters[$parameter.key]=$parameter.value
    }
    if($Kind -eq 'postgres') {
        if($actionUrn -cne 'urn:csci:microsoft:azurepostgresql:failover/1.0.0' -or
            $parameters.Count -ne 3 -or $parameters['FailoverMode'] -cne '1' -or
            $parameters['RestoreOnStop'] -cne 'false' -or $parameters['SkipIneligibleServers'] -cne 'false') {
            throw 'Native PostgreSQL forced-failover contract drifted.'
        }
    } else {
        if($actionUrn -cne 'urn:csci:microsoft:appservice:killprocess/1.0.0' -or
            $parameters.Count -ne 3 -or $parameters['ProcessName'] -cne 'dotnet' -or
            [string]::IsNullOrWhiteSpace($Selector)) { throw 'Native Linux main-process Action contract drifted.' }
        $instances=ConvertFrom-Json -InputObject $parameters['InstanceIds'] -NoEnumerate
        $zones=ConvertFrom-Json -InputObject $parameters['Zones'] -NoEnumerate
        if($instances -isnot [array] -or $zones -isnot [array] -or
            @($instances + $zones | Where-Object { $_ -isnot [string] }).Count) {
            throw 'Native instance and zone selectors must be serialized arrays of strings.'
        }
        if(($Kind -eq 'instance' -and ($instances.Count -ne 1 -or $instances[0] -cne $Selector -or $zones.Count)) -or
            ($Kind -eq 'zone' -and ($zones.Count -ne 1 -or $zones[0] -cne $Selector -or $instances.Count))) {
            throw 'Native instance/zone selector is empty, random, mixed or different from the verified selection.'
        }
    }
}

function Start-LabNativeExecution {
    param([string] $ConfigurationId,[hashtable] $Manifest,[string] $ManifestPath,[string] $EvidencePrefix)
    Assert-LabResourceId $ConfigurationId
    if(-not $Manifest.ContainsKey('activeNativeOperations')) { $Manifest.activeNativeOperations=@() }
    $intent=@{configurationId=$ConfigurationId;requestedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');pollUri=$null;status='SUBMISSION_PENDING'}
    $Manifest.activeNativeOperations+=@($intent)
    Write-LabJson $ManifestPath $Manifest
    try {
        $response=Invoke-LabArm Post "https://management.azure.com$ConfigurationId/execute?api-version=2026-08-01-preview"
        Write-LabJson "$EvidencePrefix-acceptance.json" $response
        $intent.pollUri=Get-LabNativePollUri $response
        $intent.status='ACCEPTED'
        $intent.acceptedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        Write-LabJson $ManifestPath $Manifest
        Write-Information "[$($intent.acceptedAtUtc)] Native execution accepted for $ConfigurationId." -InformationAction Continue
        return $intent
    } catch {
        $intent.status='SUBMISSION_FAILED_OR_UNCERTAIN'
        $intent.error=$_.Exception.Message
        Write-LabJson "$EvidencePrefix-submission-error.json" $intent
        Write-LabJson $ManifestPath $Manifest
        throw
    }
}
