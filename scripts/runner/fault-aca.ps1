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
# Every HTTP 202 is a new withdrawal on a distinct replica (an active lease answers 409), so the
# accepted count is the hard safety limit. It is incremented before any response parsing.
$accepted=0
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(90)
$body=@{mode=$Mode;ttlSeconds=$TtlSeconds;reason=$Reason}|ConvertTo-Json -Compress
try{
    while($accepted -lt $Count -and [DateTimeOffset]::UtcNow -lt $deadline){
        $requested=[DateTimeOffset]::UtcNow
        $entry=[ordered]@{requestedAtUtc=$requested.ToString('O');statusCode=0;replicaId=$null;error=$null}
        try{
            $response=Invoke-WebRequest "https://$($c.API_FQDN)/diagnostics/replica-fault" -Method Post -Body $body -ContentType 'application/json' `
                -Headers @{Authorization="Bearer $token";Connection='close';'X-Run-Id'="fault-$Reason"} -SkipHttpErrorCheck -TimeoutSec 10
            $entry.statusCode=$response.StatusCode
            if($response.StatusCode -eq 202){$accepted++}
            if($response.StatusCode -in @(202,409)){
                $result=$response.Content|ConvertFrom-Json
                $entry.replicaId=[string]$result.replicaId
                if($response.StatusCode -eq 202){
                    $targets.Add([ordered]@{replicaId=[string]$result.replicaId;processId=$result.processId;processStartedAtUtc=$result.processStartedAtUtc
                        requestedAtUtc=$requested.ToString('O');acceptedAtUtc=$result.acceptedAtUtc
                        expiresAtUtc=if($Mode -eq 'unready'){$result.expiresAtUtc}else{$null}})
                }
            }
        }catch{$entry.error=$_.Exception.Message}
        $entry.observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        $attempts.Add($entry)
        if($accepted -lt $Count){Start-Sleep -Milliseconds 500}
    }
    $distinct=@($targets|ForEach-Object {$_['replicaId']}|Sort-Object -Unique)
    $status=if($accepted -eq $Count -and $distinct.Count -eq $Count){'APPLIED'}else{'INCOMPLETE'}
    @{status=$status;mode=$Mode;ttlSeconds=$TtlSeconds;reason=$Reason;acceptedWithdrawals=$accepted;targets=$targets.ToArray();attempts=$attempts.ToArray()
        completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath
    if($status -ne 'APPLIED'){throw "Fault adapter reached $accepted accepted withdrawals and $($distinct.Count) distinct replicas; requested $Count."}
    "CSL_REPLICA_FAULT_APPLIED:$($distinct -join ',')"
}finally{$token=$null}
