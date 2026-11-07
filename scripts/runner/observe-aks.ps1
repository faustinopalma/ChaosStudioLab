param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string] $RunId,
    [Parameter(Mandatory)][ValidateRange(60,1800)][int] $Seconds
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$c=Get-Content "$PSScriptRoot\..\..\runner-config.json" -Raw|ConvertFrom-Json
$directory="$PSScriptRoot\..\..\results\topology-$RunId"
if(Test-Path $directory){throw 'Topology observation must use a fresh run ID.'}
New-Item -ItemType Directory $directory|Out-Null
& az login --identity --client-id $c.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if($LASTEXITCODE -ne 0){throw 'Topology observer identity login failed.'}
& az account set --subscription $c.SUBSCRIPTION_ID
if($LASTEXITCODE -ne 0){throw 'Topology observer subscription selection failed.'}
$sets=& az vmss list -g $c.NODE_RESOURCE_GROUP -o json|ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or $sets.Count -ne 7){throw 'Topology observation requires the exact seven owned scale sets.'}
$token=& az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Topology observer management authentication failed.'}
$deadline=[DateTimeOffset]::UtcNow.AddSeconds($Seconds)
$ready=$false
try{
    do{
        $sample=@{runId=$RunId;requestedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');observedAtUtc=$null;vms=@();nodes=$null;pods=$null}
        $sampleFailed=$false
        foreach($set in $sets){
            try{
                $vms=Invoke-RestMethod "https://management.azure.com$($set.id)/virtualMachines?api-version=2024-11-01&`$expand=instanceView" -Headers @{Authorization="Bearer $token"} -TimeoutSec 10
            }catch{
                $failure=$_.Exception.GetBaseException()
                $status=if($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]){[int]$_.Exception.Response.StatusCode}else{0}
                if($failure -isnot [Threading.Tasks.TaskCanceledException] -and $failure -isnot [TimeoutException] -and
                    $status -ne 429 -and $status -lt 500){throw}
                $sampleFailed=$true
                @{runId=$RunId;failedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');scaleSetId=$set.id;statusCode=$status;exceptionType=$failure.GetType().FullName}|
                    ConvertTo-Json -Compress|Add-Content "$directory\observation-errors.ndjson"
                Write-Warning "Transient ARM power-state observation failed; incomplete sample discarded. Existing 30-second evidence-gap requirement remains unchanged."
                break
            }
            foreach($vm in $vms.value){
                $power=@($vm.properties.instanceView.statuses|Where-Object {$_.code -like 'PowerState/*'})
                $sample.vms+=@(@{id=$vm.id;scaleSetId=$set.id;instanceId=$vm.instanceId;zones=@($vm.zones)
                    powerState=if($power.Count -eq 1){$power[0].code}else{'UNVERIFIED'}})
            }
        }
        if($sampleFailed){Start-Sleep -Seconds 5;continue}
        $sample.nodes=& kubectl get nodes -o json|ConvertFrom-Json
        if($LASTEXITCODE -ne 0){throw 'Independent private Kubernetes node observation failed.'}
        $sample.pods=& kubectl -n csl get pods -l app=csl-api -o json|ConvertFrom-Json
        if($LASTEXITCODE -ne 0){throw 'Independent private Kubernetes pod observation failed.'}
        $sample.observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        $sample|ConvertTo-Json -Depth 40 -Compress|Add-Content "$directory\observations.ndjson"
        if(-not $ready){Write-Output "TOPOLOGY_READY:$RunId";$ready=$true}
        Start-Sleep -Seconds 5
    }while([DateTimeOffset]::UtcNow -lt $deadline)
}finally{
    $token=$null
    @{runId=$RunId;finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json|Set-Content "$directory\completed.json"
}
