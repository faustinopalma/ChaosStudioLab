[CmdletBinding()]
param(
    [string] $AzureConfigDirectory,
    [string] $ManifestPath = (Join-Path $PSScriptRoot "..\.local\cycle-$([Guid]::NewGuid().ToString('N'))\manifest.json"),
    [int] $TunnelPort = 50222,
    [switch] $IncludeLifecycleSmoke
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
if ($AzureConfigDirectory) { $env:AZURE_CONFIG_DIR = $AzureConfigDirectory }
$AzureConfigDirectory = $env:AZURE_CONFIG_DIR
Confirm-LabContext
$startupManifest = if (Test-Path -LiteralPath $ManifestPath) { Read-LabManifest $ManifestPath } else { $null }
Assert-LabPolicyExemptions $startupManifest
Assert-LabRegionalCapabilities
$plan = Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw
foreach ($step in @('Infrastructure', 'Runner', 'Application', 'Controller')) {
    Assert-LabBuildValidation $step $plan
}
$tunnel = $null
$failed = $null
try {
    & (Join-Path $PSScriptRoot 'Build-Lab.ps1') -Step Infrastructure -ManifestPath $ManifestPath
    $m = Read-LabManifest $ManifestPath
    $o = $m.outputs['csl-infrastructure'].operations.value
    Initialize-LabMachines -ManifestPath $ManifestPath
    $m = Read-LabManifest $ManifestPath
    if (Test-Path (Join-Path $script:LabRoot 'infra\worker-bootstrap.bicep')) {
        Invoke-LabDeployment $m $ManifestPath $script:LabGroups[2] 'csl-worker-bootstrap' `
            (Join-Path $script:LabRoot 'infra\worker-bootstrap.bicep') @{
                deploymentInstanceId = $m.deploymentInstanceId
            } | Out-Null
    }
    $runnerId = $o.runnerId
    $operationsGroup = $script:LabGroups[2]
    $bastionName = $o.bastionName
    $tunnel = Start-Job -ScriptBlock {
        param($ConfigDirectory, $Group, $BastionName, $Target, $Port)
        $env:AZURE_CONFIG_DIR = $ConfigDirectory
        & az network bastion tunnel --name $BastionName --resource-group $Group --target-resource-id $Target --resource-port 22 --port $Port
    } -ArgumentList $AzureConfigDirectory, $operationsGroup, $bastionName, $runnerId, $TunnelPort
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(3)
    do {
        if ($tunnel.State -eq 'Failed') { Receive-Job $tunnel; throw 'Bastion tunnel failed.' }
        $client = [Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1', $TunnelPort); $ready = $client.Connected }
        catch [Net.Sockets.SocketException] { $ready = $false }
        finally { $client.Dispose() }
        if (-not $ready) { Start-Sleep 5 }
    } while (-not $ready -and [DateTimeOffset]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'Bastion tunnel did not become responsive.' }
    Wait-LabSsh $m (Split-Path $ManifestPath -Parent) $TunnelPort
    & (Join-Path $PSScriptRoot 'Build-Lab.ps1') -Step Runner -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    & (Join-Path $PSScriptRoot 'Build-Lab.ps1') -Step Application -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    & (Join-Path $PSScriptRoot 'Build-Lab.ps1') -Step Controller -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    & (Join-Path $PSScriptRoot 'Test-Lab.ps1') -Phase warmup -Duration 5m -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    & (Join-Path $PSScriptRoot 'Test-Lab.ps1') -Phase baseline -Duration 10m -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    & (Join-Path $PSScriptRoot 'Test-Lab.ps1') -Phase failover -Duration 12m -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    if ($IncludeLifecycleSmoke) {
        foreach ($intent in @('Reconcile', 'Suspend', 'Resume')) {
            & (Join-Path $PSScriptRoot 'Set-LabLifecycle.ps1') -Intent $intent -ManifestPath $ManifestPath -TunnelPort $TunnelPort
        }
    }
} catch {
    $failed = $_
    Write-Error $_ -ErrorAction Continue
} finally {
    if ($null -ne $tunnel) { Stop-Job $tunnel; Remove-Job $tunnel }
    if (Test-Path $ManifestPath) {
        & (Join-Path $PSScriptRoot 'Destroy-Lab.ps1') -ManifestPath $ManifestPath -Confirm:$false
    }
}
if ($null -ne $failed) { throw $failed }
if ((Read-LabManifest $ManifestPath).status -ne 'DESTROYED') {
    throw 'The exact lab groups were deleted, but external inventory changes prevent a full cleanup verdict.'
}
Write-Output "Live cycle completed and destroyed. Evidence remains beside $ManifestPath."
