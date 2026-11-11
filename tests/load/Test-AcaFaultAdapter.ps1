$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Simulates six round-robin replicas behind ingress and proves the adapter stops after exactly the
# requested accepted withdrawals, including when one accepted response body cannot be parsed.
$root=Join-Path ([IO.Path]::GetTempPath()) "csl-aca-fault-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path "$root\scripts\runner" -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\..\scripts\runner\fault-aca.ps1') "$root\scripts\runner\fault-aca.ps1"
@{RUNNER_CLIENT_ID='fixture';VAULT_NAME='fixture';API_FQDN='fixture.invalid'}|ConvertTo-Json|Set-Content "$root\runner-config.json"
$global:CslFaultFixture=@{replicas=@(0..5|ForEach-Object {@{id="replica-$_";active=$false}});next=0;corruptFirst=$false;deadline=$null}
function az { $global:LASTEXITCODE=0; if($args -contains 'secret'){'fixture-token'} }
function Invoke-WebRequest {
    param($Uri,$Method,$Body,$ContentType,$Headers,[switch]$SkipHttpErrorCheck,$TimeoutSec)
    $replica=$global:CslFaultFixture.replicas[$global:CslFaultFixture.next % 6]; $global:CslFaultFixture.next++
    if($replica.active){ return [pscustomobject]@{StatusCode=409;Content=(@{replicaId=$replica.id}|ConvertTo-Json)} }
    $replica.active=$true
    $content=if($global:CslFaultFixture.corruptFirst){$global:CslFaultFixture.corruptFirst=$false;'not-json'}else{@{replicaId=$replica.id;processId=1;processStartedAtUtc='x';acceptedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');expiresAtUtc='y'}|ConvertTo-Json}
    [pscustomobject]@{StatusCode=202;Content=$content}
}
function Start-Sleep { }
try{
    foreach($case in @(@{name='normal';corrupt=$false;expectApplied=$true},@{name='unparseable-accept';corrupt=$true;expectApplied=$false})){
        foreach($r in $global:CslFaultFixture.replicas){$r.active=$false}
        $global:CslFaultFixture.next=0;$global:CslFaultFixture.corruptFirst=$case.corrupt
        $out="$root\$($case.name).json"
        $failed=$false
        try{& "$root\scripts\runner\fault-aca.ps1" -OutputPath $out -Count 2 | Out-Null}catch{$failed=$true}
        $withdrawn=@($global:CslFaultFixture.replicas|Where-Object active).Count
        $result=Get-Content $out -Raw|ConvertFrom-Json
        if($withdrawn -ne 2 -or $result.acceptedWithdrawals -ne 2){throw "$($case.name): adapter withdrew $withdrawn replicas; exactly 2 required."}
        if($case.expectApplied -and ($failed -or $result.status -ne 'APPLIED' -or @($result.targets).Count -ne 2)){throw "$($case.name): expected APPLIED with two recorded targets."}
        if(-not $case.expectApplied -and (-not $failed -or $result.status -ne 'INCOMPLETE')){throw "$($case.name): an unrecorded accepted withdrawal must report INCOMPLETE."}
    }
    'Container Apps fault adapter withdraws exactly the requested replicas, including after an unparseable accepted response.'
}finally{Remove-Item -LiteralPath $root -Recurse -Force;Remove-Variable CslFaultFixture -Scope Global -ErrorAction SilentlyContinue}
