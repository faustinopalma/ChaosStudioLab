param(
    [Parameter(Mandatory)][string] $OutputPath,
    [ValidateRange(1,5)][int] $Count = 2,
    [ValidateRange(1,600)][int] $TtlSeconds = 360,
    [ValidateSet('unready','exit')][string] $Mode = 'unready',
    [ValidatePattern('^[A-Za-z0-9._-]{1,80}$')][string] $Reason = 'HA-REPLICA-001'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$c=Get-Content "$PSScriptRoot\..\..\runner-config.json" -Raw|ConvertFrom-Json
& az login --identity --client-id $c.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if($LASTEXITCODE -ne 0){throw 'Fault adapter identity login failed.'}
$token=& az keyvault secret show --vault-name $c.VAULT_NAME --name diagnostics-token --query value -o tsv
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Fault adapter secret retrieval failed.'}
$targets=[Collections.Generic.List[object]]::new()
$attempts=[Collections.Generic.List[object]]::new()
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(90)
$body=@{mode=$Mode;ttlSeconds=$TtlSeconds;reason=$Reason}|ConvertTo-Json -Compress
try{
    while($targets.Count -lt $Count -and [DateTimeOffset]::UtcNow -lt $deadline){
        $requested=[DateTimeOffset]::UtcNow
        $entry=[ordered]@{requestedAtUtc=$requested.ToString('O');statusCode=0;replicaId=$null;error=$null}
        try{
            $response=Invoke-WebRequest "https://$($c.API_FQDN)/diagnostics/replica-fault" -Method Post -Body $body -ContentType 'application/json' `
                -Headers @{Authorization="Bearer $token";Connection='close';'X-Run-Id'="fault-$Reason"} -SkipHttpErrorCheck -TimeoutSec 10
            $entry.statusCode=$response.StatusCode
            if($response.StatusCode -in @(202,409)){
                $result=$response.Content|ConvertFrom-Json
                $entry.replicaId=$result.replicaId
                if($response.StatusCode -eq 202 -and $result.replicaId -notin $targets.replicaId){
                    $targets.Add([ordered]@{replicaId=$result.replicaId;processId=$result.processId;processStartedAtUtc=$result.processStartedAtUtc
                        requestedAtUtc=$requested.ToString('O');acceptedAtUtc=$result.acceptedAtUtc
                        expiresAtUtc=if($Mode -eq 'unready'){$result.expiresAtUtc}else{$null}})
                }
            }
        }catch{$entry.error=$_.Exception.Message}
        $entry.observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        $attempts.Add($entry)
        if($targets.Count -lt $Count){Start-Sleep -Milliseconds 500}
    }
    $status=if($targets.Count -eq $Count){'APPLIED'}else{'INCOMPLETE'}
    @{status=$status;mode=$Mode;ttlSeconds=$TtlSeconds;reason=$Reason;targets=$targets.ToArray();attempts=$attempts.ToArray()
        completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath
    if($status -ne 'APPLIED'){throw "Fault adapter reached $($targets.Count) of $Count distinct replicas."}
    "CSL_REPLICA_FAULT_APPLIED:$($targets.replicaId -join ',')"
}finally{$token=$null}
