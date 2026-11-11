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
$base="https://management.azure.com/subscriptions/$($c.SUBSCRIPTION_ID)/resourceGroups/$($c.APP_RESOURCE_GROUP)/providers/Microsoft.App/containerApps/$($c.APP_NAME)"
$token=& az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Topology observer management authentication failed.'}
$headers=@{Authorization="Bearer $token"}
$revision=(Invoke-RestMethod "$base`?api-version=2026-07-01" -Headers $headers -TimeoutSec 10).properties.latestRevisionName
$deadline=[DateTimeOffset]::UtcNow.AddSeconds($Seconds)
$ready=$false
try{
    do{
        $sample=[ordered]@{runId=$RunId;revision=$revision;requestedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');observedAtUtc=$null;replicas=@()}
        try{
            $page=Invoke-RestMethod "$base/revisions/$revision/replicas?api-version=2026-07-01" -Headers $headers -TimeoutSec 10
        }catch{
            $status=if($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]){[int]$_.Exception.Response.StatusCode}else{0}
            if($status -in @(401,403)){throw}
            @{runId=$RunId;failedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');statusCode=$status;exceptionType=$_.Exception.GetBaseException().GetType().FullName}|
                ConvertTo-Json -Compress|Add-Content "$directory\observation-errors.ndjson"
            Start-Sleep -Seconds 5
            continue
        }
        foreach($replica in $page.value){
            $container=@($replica.properties.containers)[0]
            $sample.replicas+=@([ordered]@{name=$replica.name;runningState=$replica.properties.runningState;createdTime=$replica.properties.createdTime
                ready=$container.PSObject.Properties['ready']?.Value;started=$container.PSObject.Properties['started']?.Value;restartCount=$container.PSObject.Properties['restartCount']?.Value;containerState=$container.PSObject.Properties['runningState']?.Value})
        }
        $sample.observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        $sample|ConvertTo-Json -Depth 10 -Compress|Add-Content "$directory\observations.ndjson"
        if(-not $ready){Write-Output "TOPOLOGY_READY:$RunId";$ready=$true}
        Start-Sleep -Seconds 5
    }while([DateTimeOffset]::UtcNow -lt $deadline)
}finally{
    $token=$null;$headers=$null
    @{runId=$RunId;finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json|Set-Content "$directory\completed.json"
}
