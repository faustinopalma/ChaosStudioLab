. (Join-Path $PSScriptRoot 'Lab.Native.ps1')

function Assert-AksNativeDefinition {
    param([hashtable] $Configuration,[hashtable] $Scenario,[string[]] $TargetIds,[string] $Kind,[string] $Zone='1')
    foreach($id in $TargetIds){Assert-LabResourceId $id}
    $actual=@($Configuration.properties.resourceTargeting.include.resources)
    if(@(Compare-Object @($TargetIds|Sort-Object) @($actual|Sort-Object)).Count -or
        (Get-LabNativeScenarioId $Configuration) -ine $Scenario.id -or $Scenario.properties.actions.Count -ne 1){
        throw 'Native configuration targets or Scenario binding differ from the exact owned intent.'
    }
    $action=$Scenario.properties.actions[0]
    $urn=Get-LabNativeActionUrn $action.actionId
    $parameters=@{}
    foreach($p in $action.parameters){
        if($parameters.ContainsKey($p.key) -or $p.value -isnot [string]){throw 'Invalid native string parameter contract.'}
        $parameters[$p.key]=$p.value
    }
    if($Kind -eq 'database'){
        if($urn -cne 'urn:csci:microsoft:azurepostgresql:failover/1.0.0' -or $TargetIds.Count -ne 1 -or
            $action.duration -ne 'PT1M' -or $parameters.Count -ne 3 -or $parameters.FailoverMode -cne '1' -or
            $parameters.RestoreOnStop -cne 'false' -or $parameters.SkipIneligibleServers -cne 'false'){throw 'Native PostgreSQL forced-failover contract differs.'}
    }else{
        if($Kind -notin @('node','zone') -or $urn -cne 'urn:csci:microsoft:virtualmachinescaleset:shutdown/1.0.0' -or
            $action.duration -ne 'PT7M' -or $parameters.Count -ne 2 -or $parameters.GracefulShutdown -cne 'false'){
            throw 'Native abrupt seven-minute VMSS shutdown contract differs.'
        }
        $zones=ConvertFrom-Json $parameters.Zones -NoEnumerate
        if($zones -isnot [array] -or ($Kind -eq 'node' -and ($TargetIds.Count -ne 1 -or $zones.Count)) -or
            ($Kind -eq 'zone' -and ($TargetIds.Count -ne 3 -or $zones.Count -ne 1 -or $zones[0] -cne $Zone))){
            throw 'Native exact single-node or selected-zone selector differs.'
        }
    }
}

function Confirm-AksNativeValidation {
    param([string] $ConfigurationId,[string[]] $TargetIds,[string] $EvidencePrefix)
    $acceptance=Invoke-LabArm Post "https://management.azure.com$ConfigurationId/validate?api-version=2026-08-01-preview"
    Write-LabJson "$EvidencePrefix-acceptance.json" $acceptance
    $result=Wait-LabNativeOperation (Get-LabNativePollUri $acceptance) $EvidencePrefix -TimeoutSeconds 300 -AllowFailedTerminal -OperationKind Validation
    Write-LabJson "$EvidencePrefix-terminal.json" $result
    $p=$result.properties
    $actual=@($p.resources|ForEach-Object id)
    $validationErrors=if($p.ContainsKey('validationErrors') -and $null -ne $p.validationErrors){$p.validationErrors}else{@{permission=@();resource=@()}}
    if($p.status -ne 'Succeeded' -or @($p.errors|Where-Object {$null -ne $_}).Count -or
        @($validationErrors.permission|Where-Object {$null -ne $_}).Count -or @($validationErrors.resource|Where-Object {$null -ne $_}).Count -or
        @(Compare-Object @($TargetIds|Sort-Object) @($actual|Sort-Object)).Count){
        throw "BLOCKED: clean exact-target native validation missing; status=$($p.status), errors=$($p|ConvertTo-Json -Depth 20 -Compress)"
    }
    return $result
}

function Complete-AksNativeExecution {
    param([hashtable] $Intent,[hashtable] $Definition,[hashtable] $Manifest,[string] $ManifestPath,[string] $EvidencePrefix)
    $result=Wait-LabNativeOperation $Intent.pollUri $EvidencePrefix -TimeoutSeconds 900 -AllowFailedTerminal
    Write-LabJson "$EvidencePrefix-terminal.json" $result
    $Intent.terminalStatus=$result.properties.status
    $Intent.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
    $Intent.status='FAILED_RECONCILED'
    Write-LabJson $ManifestPath $Manifest
    if($result.properties.status -ne 'Succeeded'){
        throw "BLOCKED: native runtime $($result.properties.status): $($result.properties.errors|ConvertTo-Json -Depth 20 -Compress)"
    }
    $actualTargets=@($result.properties.resources|ForEach-Object id)
    if(@(Compare-Object @($Definition.targets|Sort-Object) @($actualTargets|Sort-Object)).Count){throw 'Native execution actual resources differ from intended targets.'}
    $compiled=$result.properties.scenarioRunJson|ConvertFrom-Json -AsHashtable
    $actions=@($compiled.actions.Values)
    $expected=$Definition.scenario.properties.actions[0]
    if($actions.Count -lt 1){throw 'Compiled native execution has no Actions.'}
    $compiledTargets=@()
    foreach($action in $actions){
        $p=$action.properties
        if($p.faultUrn -cne (Get-LabNativeActionUrn $expected.actionId) -or $p.faultParameters.Count -ne $expected.parameters.Count){throw 'Compiled native Action contract differs.'}
        foreach($parameter in $expected.parameters){
            if($p.faultParameters[$parameter.key] -cne $parameter.value){throw "Compiled native parameter $($parameter.key) differs."}
        }
        $compiledTargets+=@($p.targetResources|ForEach-Object fullyQualifiedIdentifier)
    }
    if(@(Compare-Object @($Definition.targets|Sort-Object) @($compiledTargets|Sort-Object -Unique)).Count -or
        @($result.properties.errors|Where-Object {$null -ne $_}).Count -or
        -not @($result.properties.scenarioRunSummary).Count -or
        @($result.properties.scenarioRunSummary|Where-Object state -ne 'Succeeded').Count){throw 'Native Action-level terminal evidence is incomplete.'}
    $principal=$Manifest.outputs.infrastructure.workload.value.chaosPrincipalId
    if($result.properties.managedIdentityPrincipalId -ine $principal){
        if($Definition.kind -eq 'database'){
            Confirm-LabNativePostgresIdentity $result $Definition.scenario $Definition.targets[0] $principal $EvidencePrefix
        }else{
            Confirm-AksNativeComputeIdentity $result $Definition $principal $EvidencePrefix
        }
    }
    $Intent.status='SUCCEEDED'
    if($Definition.kind -eq 'database'){$Manifest.lastPostgresFaultFinishedAtUtc=$Intent.finishedAtUtc}
    Write-LabJson $ManifestPath $Manifest
    return $result
}

function Confirm-AksNativeComputeIdentity {
    param([hashtable] $Result,[hashtable] $Definition,[string] $PrincipalId,[string] $EvidencePrefix)
    $start=[DateTimeOffset]$Result.properties.startTime
    $end=[DateTimeOffset]$Result.properties.endTime
    if($end -le $start -or -not $Definition.targetVmIds.Count){throw 'Compute identity audit requires the explicit execution interval and exact VM inventory.'}
    $deadline=[DateTimeOffset]::UtcNow.AddMinutes(15)
    $index=0
    do{
        $events=@(Invoke-LabAz @('monitor','activity-log','list','-g',$script:LabGroups[3],
            '--start-time',$start.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'),
            '--end-time',$end.AddMinutes(15).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'),'--max-events','1000','-o','json')|ConvertFrom-Json -AsHashtable)
        Write-LabJson "$EvidencePrefix-identity-activity-$($index.ToString('D3')).json" $events
        $index++
        if($events.Count -ge 1000){throw 'Compute Activity Log query may be truncated.'}
        $operations=@($events|Where-Object {$_.operationName.value -imatch '^Microsoft.Compute/virtualMachineScaleSets(/virtualMachines)?/(powerOff|deallocate)/action$' -and
            ($_.resourceId -in $Definition.targetVmIds -or $_.resourceId -in $Definition.targets) -and
            [DateTimeOffset]$_.eventTimestamp -ge $start})
        $proofs=@()
        foreach($vmId in $Definition.targetVmIds){
            $setId=$vmId -replace '/virtualMachines/[^/]+$',''
            $completed=@($operations|Where-Object {($_.resourceId -ieq $vmId -or $_.resourceId -ieq $setId) -and $_.status.value -eq 'Succeeded'})
            foreach($success in $completed){
                $begin=@($operations|Where-Object {$_.status.value -eq 'Started' -and $_.resourceId -ieq $success.resourceId -and
                    $_.correlationId -eq $success.correlationId -and [DateTimeOffset]$_.eventTimestamp -le $end})
                if($begin.Count -ne 1 -or -not $success.correlationId -or [DateTimeOffset]$begin[0].eventTimestamp -ge [DateTimeOffset]$success.eventTimestamp){continue}
                foreach($event in @($begin[0],$success)){
                    if($event.caller -ine $PrincipalId -or $event.claims['http://schemas.microsoft.com/identity/claims/objectidentifier'] -ine $PrincipalId){
                        throw 'Compute shutdown authenticated caller/object claim differs from Workspace identity.'
                    }
                }
                $proofs+=@(@{vmId=$vmId;resourceId=$success.resourceId;correlationId=$success.correlationId;started=$begin[0].eventTimestamp;completed=$success.eventTimestamp})
                break
            }
        }
        if($proofs.Count -eq $Definition.targetVmIds.Count){break}
        $remaining=($deadline-[DateTimeOffset]::UtcNow).TotalSeconds
        if($remaining -le 0){throw 'Compute identity audit deadline expired without correlated authenticated shutdown evidence for every intended VM.'}
        Write-Information "Waiting for exact-owned compute Activity Log ingestion; $([Math]::Ceiling($remaining)) seconds remain; native Action is not resubmitted." -InformationAction Continue
        Start-Sleep -Seconds 15
    }while($true)
    Write-LabJson "$EvidencePrefix-identity-proof.json" @{status='PASS';source='Azure Activity Log';expectedPrincipalId=$PrincipalId
        reportedPrincipalId=$Result.properties.managedIdentityPrincipalId;operations=$proofs;activityQueries=$index}
    Write-Warning 'Compute native principal metadata differs; correlated shutdown caller/object claims independently authenticate the exact Workspace identity.'
}
