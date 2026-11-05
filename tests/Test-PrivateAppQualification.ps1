$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-private-qualification-$([Guid]::NewGuid().ToString('N'))"
foreach ($directory in @('scripts\runner','tests\load','results')) {
    New-Item -ItemType Directory -Path (Join-Path $fixture $directory) -Force | Out-Null
}
foreach ($name in @('verify.ps1','qualify-app.ps1')) {
    Copy-Item (Join-Path $root "scripts\runner\$name") (Join-Path $fixture "scripts\runner\$name")
}
Copy-Item (Join-Path $root 'tests\load\evaluate-durability.ps1') (Join-Path $fixture 'tests\load')
@{API_FQDN='10.81.10.5';SCM_FQDN='10.81.10.6';SOURCE_REVISION='fixture-source'
    RUNNER_CLIENT_ID='fixture-runner';SUBSCRIPTION_ID='fixture-subscription';VAULT_NAME='fixture-vault'} |
    ConvertTo-Json | Set-Content (Join-Path $fixture 'runner-config.json')
$qualificationFixtureState = @{
    orders=@{};healthSample=0;businessSample=0
    loseNextAcknowledgement=$false;badBusinessChecksum=$false
}
function az {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'keyvault') { 'fixture-only-not-a-credential' }
}
function Invoke-WebRequest {
    param($Uri,$Method='Get',$Body,$Headers,$ContentType,$TimeoutSec,$WebSession,[switch]$SkipHttpErrorCheck)
    $status = 200
    $content = @{}
    $instance = 0
    if ($Uri -like '*/health/ready') { $content=@{status='ready'} }
    elseif ($Uri -like '*/health/live') {
        $instance=$qualificationFixtureState.healthSample++ % 6
        $content=@{status='live';instanceId="instance-$instance";processId=100+$instance;revision='fixture-source'}
    } elseif ($Method -eq 'Post') {
        $request=$Body | ConvertFrom-Json
        $canonical=$request.payload | ConvertTo-Json -Compress
        $checksum=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
        if ($qualificationFixtureState.orders.ContainsKey($request.operationId)) {
            $content=$qualificationFixtureState.orders[$request.operationId]
            if ($checksum -ne $content.payloadSha256) { $status=409 }
        } else {
            $content=@{operationId=$request.operationId;payloadSha256=$checksum}
            $qualificationFixtureState.orders[$request.operationId]=$content
            $status=201
            if ($qualificationFixtureState.loseNextAcknowledgement) {
                $qualificationFixtureState.loseNextAcknowledgement=$false
                throw [Net.Http.HttpRequestException]::new('Fixture committed write, then lost response.')
            }
        }
    } elseif ($null -eq $Headers -or -not $Headers.ContainsKey('Authorization')) { $status=401 }
    else {
        $instance=$qualificationFixtureState.businessSample++ % 6
        $id=($Uri -split '/')[-1]
        if ($qualificationFixtureState.orders.ContainsKey($id)) {
            $content=$qualificationFixtureState.orders[$id].Clone()
            if ($qualificationFixtureState.badBusinessChecksum) { $content.payloadSha256='0'*64 }
        } else { $status=404 }
    }
    [pscustomobject]@{StatusCode=$status;Content=($content | ConvertTo-Json -Compress);Headers=@{
        'X-Lab-Instance-Id'=@("instance-$instance");'X-Lab-Process-Id'=@([string](100+$instance))
        'X-Lab-Process-Start-Utc'=@('2026-01-01T00:00:00.0000000+00:00')
    }}
}
function Invoke-RestMethod {
    param($Uri,$Headers,$TimeoutSec)
    (Invoke-WebRequest -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec).Content | ConvertFrom-Json
}
try {
    & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1
    & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1
    $settleProof=@((Get-Content (Join-Path $fixture 'results\private-verification.json') -Raw | ConvertFrom-Json).checks | Where-Object name -eq 'Post-deployment worker stability')
    if ($settleProof.Count -ne 1 -or $settleProof[0].status -ne 'PASS' -or $settleProof[0].detail.observedProcesses -lt 1) {
        throw 'Verification did not record the post-deployment worker stability gate.'
    }
    $journal=Join-Path $fixture 'results\private-verification-writes.ndjson'
    $entries=@(Get-Content $journal | ForEach-Object { $_ | ConvertFrom-Json })
    if ($entries.Count -ne 2 -or @($entries | Where-Object { -not $_.success -or -not $_.acknowledged }).Count) {
        throw 'Bootstrap verification did not preserve valid acknowledged-write history.'
    }
    $qualificationFixtureState.loseNextAcknowledgement=$true
    $caught=$false
    try { & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1 }
    catch { $caught=$_.Exception.Message -like '*committed write, then lost response*' }
    if (-not $caught) { throw 'A write transport failure was hidden.' }
    & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1
    $durability=Get-Content (Join-Path $fixture 'results\private-verification-durability.json') -Raw | ConvertFrom-Json
    if ($durability.status -ne 'PASS' -or $durability.issuedUniqueWrites -ne 4 -or
        $durability.acknowledgedUniqueWrites -ne 3 -or $durability.retainedWrites -ne 4) {
        throw 'Reverification omitted earlier writes or the committed response-loss case.'
    }
    $output=Join-Path $fixture 'results\qualification.json'
    & (Join-Path $fixture 'scripts\runner\qualify-app.ps1') -Samples 12 -OutputPath $output
    $qualification=Get-Content $output -Raw | ConvertFrom-Json
    if ($qualification.status -ne 'COLLECTED_REQUIRES_INVENTORY_GATE' -or $qualification.observations.Count -ne 24) {
        throw 'Private qualification claimed a placement PASS or omitted actual probe records.'
    }
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\Lab.Common.ps1'),[ref]$tokens,[ref]$errors)
    foreach ($name in @('Assert-LabAppServicePlan','Assert-LabAppServicePlacement')) {
        $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
    $plan=@{kind='linux';properties=@{reserved=$true;zoneRedundant=$true;perSiteScaling=$false;maximumNumberOfZones=3};sku=@{capacity=6}}
    $instances=@(0..5 | ForEach-Object { @{name="instance-$_";properties=@{physicalZone="fixture-az$([int][Math]::Floor($_/2)+1)"}} })
    Assert-LabAppServicePlacement $plan $instances $qualification.observations
    $qualificationFixtureState.badBusinessChecksum=$true
    $caught=$false
    try { & (Join-Path $fixture 'scripts\runner\qualify-app.ps1') -Samples 12 -OutputPath $output }
    catch { $caught=$_.Exception.Message -like '*business participation failed*checksum*' }
    $partial=Get-Content $output -Raw | ConvertFrom-Json
    if (-not $caught -or $partial.status -ne 'FAIL' -or -not $partial.error) {
        throw 'A failed qualification did not retain an explicit partial failure.'
    }
    $qualificationFixtureState.badBusinessChecksum=$false
    $historyIds=@()
    foreach($number in 1..2) {
        $runId=([string]$number)*32
        $id=[Guid]::NewGuid().ToString()
        $historyIds+=@($id)
        $checksum='a'*64
        $qualificationFixtureState.orders[$id]=@{operationId=$id;payloadSha256=$checksum}
        $directory=Join-Path $fixture "results\$runId"
        New-Item -ItemType Directory -Path $directory | Out-Null
        @{runId=$runId;type='attempt';operation='write';operationId=$id;expectedChecksum=$checksum
            status=201;success=$true;responseChecksum=$checksum} |
            ConvertTo-Json -Compress | Set-Content (Join-Path $directory 'attempts.ndjson')
    }
    & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1 -VerifyAllRuns
    $history=Get-Content (Join-Path $fixture 'results\all-runs-durability.json') -Raw | ConvertFrom-Json
    if($history.status -ne 'PASS' -or $history.runs.Count -ne 2) { throw 'Final verification did not reconcile every earlier measurement run.' }
    $qualificationFixtureState.orders.Remove($historyIds[0])
    $caught=$false
    try { & (Join-Path $fixture 'scripts\runner\verify.ps1') -SettleSeconds 1 -VerifyAllRuns } catch { $caught=$true }
    $history=Get-Content (Join-Path $fixture 'results\all-runs-durability.json') -Raw | ConvertFrom-Json
    if(-not $caught -or $history.status -ne 'FAIL' -or $history.runs[0].lostAcknowledgedWrites -ne 1) {
        throw 'Final verification hid the loss of an earlier acknowledged measurement write.'
    }
    'Private three-zone participation, every historical smoke/measurement write, lost-response reconciliation and explicit old-write loss verified.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse
}
