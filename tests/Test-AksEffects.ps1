$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tmp=Join-Path ([IO.Path]::GetTempPath()) "csl-aks-effects-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $tmp|Out-Null
$start=[DateTimeOffset]'2026-11-07T00:00:00Z'
$pg=@{id='/subscriptions/test/resourceGroups/owned/providers/Microsoft.DBforPostgreSQL/flexibleServers/pg';state='Ready';availabilityZone='1';highAvailability=@{mode='ZoneRedundant';state='Healthy';standbyAvailabilityZone='2'}}
$pgAfter=@{id=$pg.id;state='Ready';availabilityZone='2';highAvailability=@{mode='ZoneRedundant';state='Healthy';standbyAvailabilityZone='1'}}
$targetIds=@('vm1','vm2','vm3')
$events=[Collections.Generic.List[string]]::new()
for($second=0;$second -lt 720;$second++){
    $time=$start.AddSeconds($second).ToString('O')
    $events.Add((@{runId='fixture';type='canaryTick';scheduledAtUtc=$time;success=$true}|ConvertTo-Json -Compress))
    for($i=0;$i -lt 20;$i++){
        $events.Add((@{runId='fixture';type='businessOperation';phase='app-zone';operation='read';startedAtUtc=$time;success=$true;durationMs=50}|ConvertTo-Json -Compress))
    }
    $events.Add((@{runId='fixture';type='attempt';recordedAtUtc=$time;success=$true;instanceId=if($second%2){'u2'}else{'u3'}}|ConvertTo-Json -Compress))
}
Set-Content "$tmp\attempts.ndjson" $events
$topology=@(for($second=0;$second -le 710;$second+=10){
    @{requestedAtUtc=$start.AddSeconds($second).ToString('O');observedAtUtc=$start.AddSeconds($second+1).ToString('O')
        vms=@(for($i=1;$i -le 9;$i++){
            @{id="vm$i";powerState=if($i -le 3 -and $second -ge 50 -and $second -le 390){'PowerState/stopped'}else{'PowerState/running'}}
        })
        nodes=@{items=@(@{metadata=@{name='n2';labels=@{'topology.kubernetes.io/zone'='swedencentral-2'}}},@{metadata=@{name='n3';labels=@{'topology.kubernetes.io/zone'='swedencentral-3'}}})}
        pods=@{items=@(@{metadata=@{uid='u2'};spec=@{nodeName='n2'}},@{metadata=@{uid='u3'};spec=@{nodeName='n3'}})}
    }
})
$observer=@(for($second=0;$second -lt 720;$second++){
    foreach($kind in @('live','dependencies')){
        @{kind=$kind;requestedAtUtc=$start.AddSeconds($second).ToString('O');observedAtUtc=$start.AddSeconds($second).ToString('O')
            statusCode=200;processId='1';dependencyStatus='available'}
    }
})
function Save-Events([string] $Name,[object[]] $Values){$Values|ForEach-Object {$_|ConvertTo-Json -Depth 15 -Compress}|Set-Content "$tmp\$Name.ndjson"}
function Check([string] $Case,[string] $TestId,[string] $ExpectedStatus,[hashtable] $After=$pgAfter){
    $caseRoot="$tmp\$Case";New-Item -ItemType Directory $caseRoot|Out-Null
    & "$root\tests\load\evaluate-aks.ps1" -AttemptsPath "$tmp\attempts.ndjson" -TopologyPath "$tmp\topology.ndjson" `
        -ObserverPath "$tmp\observer.ndjson" -CaseRoot $caseRoot -TestId $TestId -SubmittedAtUtc $start.AddSeconds(30) `
        -TargetVmIds $targetIds -PostgresBefore $pg -PostgresAfter $After
    $result=Get-Content "$caseRoot\effect-verdict.json" -Raw|ConvertFrom-Json
    if($result.status -ne $ExpectedStatus){throw "$Case expected $ExpectedStatus, actual $($result.status): $($result.reason)"}
}
try{
    Save-Events topology $topology;Save-Events observer $observer
    Check sustained-zone 'HA-ZONE-COMPUTE-001' PASS
    $short=@($topology|ForEach-Object {$s=$_|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
        if([DateTimeOffset]$s.observedAtUtc -ge $start.AddSeconds(340)){foreach($vm in $s.vms){$vm.powerState='PowerState/running'}};$s})
    Save-Events topology $short
    Check short-fault 'HA-ZONE-COMPUTE-001' INCONCLUSIVE
    $gapped=@($topology|Where-Object {[DateTimeOffset]$_.observedAtUtc -lt $start.AddSeconds(170) -or [DateTimeOffset]$_.observedAtUtc -gt $start.AddSeconds(220)})
    Save-Events topology $gapped
    Check observer-gap 'HA-ZONE-COMPUTE-001' INCONCLUSIVE
    Save-Events topology $topology
    Check missing-zone-swap 'HA-COMBINED-001' INCONCLUSIVE $pg
    'AKS sustained >=300-second shutdown, observer-gap and database zone-swap evidence tests passed.'
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force}
