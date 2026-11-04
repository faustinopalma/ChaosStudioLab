$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$compiled = & az bicep build --file (Join-Path $root 'infra\main.bicep') --stdout
if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }
$template = ($compiled -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable

function Get-TemplateResources([hashtable] $Template) {
    foreach ($resource in $Template.resources) {
        $resource
        if ($resource.type -eq 'Microsoft.Resources/deployments') {
            Get-TemplateResources $resource.properties.template
        }
    }
}
function Assert-Contract([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$resources = @(Get-TemplateResources $template)
$containerEnvironment = @($resources | Where-Object type -eq 'Microsoft.App/managedEnvironments')[0]
Assert-Contract ($containerEnvironment.properties.vnetConfiguration.internal -eq $true -and
    $containerEnvironment.properties.publicNetworkAccess -eq 'Disabled' -and
    $containerEnvironment.properties.zoneRedundant -eq $true) 'The environment must retain internal ingress, disabled public access and zone redundancy.'
$containerEndpoint = @($resources | Where-Object name -eq 'pe-csl-container-apps')[0]
Assert-Contract ($containerEndpoint.properties.privateLinkServiceConnections[0].properties.groupIds[0] -eq
    'managedEnvironments') 'Container Apps Private Link must use the live provider-advertised plural group ID.'
$operationsDeployment = @($template.resources | Where-Object name -eq 'csl-operations')[0]
Assert-Contract (@($operationsDeployment.dependsOn | Where-Object { $_ -match 'csl-workload' }).Count -eq 0) 'Operations must use the already-created migration identity without waiting for workload provisioning.'
Assert-Contract ($template.parameters.location.defaultValue -eq 'swedencentral') 'The deployment default must use the current verified regional candidate.'
foreach ($deploymentName in @('csl-network-core', 'csl-workload', 'csl-operations', 'csl-private-dns-links')) {
    $deployment = @($template.resources | Where-Object name -eq $deploymentName)[0]
    Assert-Contract ($deployment.properties.parameters.location.value -eq "[parameters('location')]") "Selected location is not propagated to $deploymentName."
}
$networkTemplate = @($template.resources | Where-Object name -eq 'csl-network-core')[0].properties.template
$dnsTemplate = @($template.resources | Where-Object name -eq 'csl-private-dns-links')[0].properties.template
$workloadDeployment = @($template.resources | Where-Object name -eq 'csl-workload')[0]
Assert-Contract ($workloadDeployment.properties.parameters.migrationPrincipalId.value -eq
    "[parameters('prerequisitePrincipalIds').migration]") 'PostgreSQL administrator IDs must use the live prerequisite snapshot.'
foreach ($name in @('csl-control-contributor-network', 'csl-control-contributor-workload', 'csl-control-contributor-operations')) {
    $roleDeployment = @($template.resources | Where-Object name -eq $name)[0]
    Assert-Contract ($roleDeployment.properties.parameters.principalId.value -eq
        "[parameters('prerequisitePrincipalIds').control]") 'Controller role IDs must be resolvable before deployment.'
}
$runnerAccess = @($template.resources | Where-Object name -eq 'csl-runner-workload-access')[0]
Assert-Contract ($runnerAccess.properties.parameters.runnerPrincipalId.value -eq
    "[parameters('prerequisitePrincipalIds').runner]") 'Runner role IDs must use the verified prerequisite snapshot.'
$wrapperJson = & az bicep build --file (Join-Path $root 'infra\validation.bicep') --stdout
if ($LASTEXITCODE -ne 0) { throw 'Validation-wrapper compilation failed.' }
$wrapper = ($wrapperJson -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable
$workerJson = & az bicep build --file (Join-Path $root 'infra\worker-bootstrap.bicep') --stdout
if ($LASTEXITCODE -ne 0) { throw 'Worker-bootstrap compilation failed.' }
$workerTemplate = ($workerJson -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable
$memberships = @($workerTemplate.resources | Where-Object type -eq 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers')
$workerExtensions = @($workerTemplate.resources | Where-Object type -eq 'Microsoft.Compute/virtualMachines/extensions')
Assert-Contract ($memberships.Count -eq 2 -and $workerExtensions.Count -eq 2) 'Expected two worker memberships and extensions.'
foreach ($membership in $memberships) {
    Assert-Contract (@($membership['dependsOn'] | Where-Object { $_ -match '/extensions' }).Count -eq 0) 'Worker membership must be created before extension onboarding.'
}
foreach ($extension in $workerExtensions) {
    Assert-Contract (@($extension.dependsOn | Where-Object { $_ -match 'hybridRunbookWorkers' }).Count -eq 1 -and
        $extension.properties.forceUpdateTag -eq "[parameters('deploymentInstanceId')]") 'Extension enable must follow membership and support repair of the failed initial enable.'
}
Assert-Contract (@($wrapper.resources | Where-Object type -eq 'Microsoft.Resources/deployments')[0].properties.parameters.prerequisitePrincipalIds.value -eq
    "[parameters('prerequisitePrincipalIds')]") 'Validation and real deployment must use the same explicit principal snapshot.'
Assert-Contract ($networkTemplate.variables.privateDnsZoneNames -match 'parameters\(''location''\)' -and
    $dnsTemplate.variables.zoneNames -match 'parameters\(''location''\)') 'Container Apps private DNS must follow the selected region.'
$vault = @($resources | Where-Object type -eq 'Microsoft.KeyVault/vaults')[0]
Assert-Contract (-not $vault.properties.ContainsKey('enablePurgeProtection')) 'Omit purge protection on create; the Key Vault API rejects explicit false.'
$monitorEndpoint = @($resources | Where-Object name -eq 'pe-csl-monitor')[0]
Assert-Contract (@($monitorEndpoint.dependsOn | Where-Object { $_ -match 'scopedResources' }).Count -eq 2) 'Monitor endpoint must wait for both scoped-resource associations.'
$retired = @($resources | Where-Object {
    $_.type -in @('Microsoft.Network/azureFirewalls', 'Microsoft.Network/firewallPolicies',
        'Microsoft.Network/firewallPolicies/ruleCollectionGroups', 'Microsoft.Network/routeTables')
})
Assert-Contract ($retired.Count -eq 0) 'Firewall, policy or route table remains in the deployment.'
$vnets = @($resources | Where-Object type -eq 'Microsoft.Network/virtualNetworks')
Assert-Contract ($vnets.Count -eq 2) 'Expected exactly two VNets.'
foreach ($vnet in $vnets) {
    Assert-Contract (-not $vnet.properties.ContainsKey('dhcpOptions')) 'Custom appliance DNS remains.'
    foreach ($subnet in $vnet.properties.subnets) {
        Assert-Contract (-not $subnet.properties.ContainsKey('routeTable')) 'An appliance route table remains attached.'
    }
}
$operations = @($vnets | Where-Object name -eq 'vnet-csl-operations')[0]
$vmSubnet = @($operations.properties.subnets | Where-Object name -eq 'operations')[0]
Assert-Contract ($vmSubnet.properties.defaultOutboundAccess -eq $false) 'VM default outbound access must be disabled.'
Assert-Contract ($vmSubnet.properties.natGateway.id -match 'natGateways') 'VMs lack explicit NAT egress.'
Assert-Contract (@($resources | Where-Object type -eq 'Microsoft.Network/natGateways').Count -eq 1) 'Expected one NAT Gateway.'
Assert-Contract (@($operations.properties.subnets | Where-Object name -eq 'AzureBastionSubnet').Count -eq 1) 'Bastion subnet must be in operations.'
Assert-Contract ($template.parameters.operationsBastionSubnetPrefix.defaultValue -eq '10.82.2.0/26') 'Bastion address range drifted.'
foreach ($parameter in @('networkResourceGroupName', 'workloadResourceGroupName', 'operationsResourceGroupName')) {
    Assert-Contract (-not $template.parameters[$parameter].ContainsKey('defaultValue')) 'Real group names must be supplied through private parameters.'
}
$bastion = @($resources | Where-Object type -eq 'Microsoft.Network/bastionHosts')
Assert-Contract ($bastion.Count -eq 1 -and $bastion[0].name -eq 'bas-csl-operations') 'Unexpected Bastion placement/name.'
$publicIps = @($resources | Where-Object type -eq 'Microsoft.Network/publicIPAddresses')
$twoAddressCount = "[length(createArray('egress', 'bastion'))]"
Assert-Contract ($publicIps.Count -eq 1 -and $publicIps[0].copy.count -eq $twoAddressCount) 'Expected the two-address NAT/Bastion loop.'
foreach ($ip in $publicIps) {
    Assert-Contract ($ip.sku.name -eq 'Standard' -and
        $ip.properties.publicIPAllocationMethod -eq 'Static' -and
        $ip.properties.publicIPAddressVersion -eq 'IPv4' -and
        -not $ip.properties.ContainsKey('ipTags')) 'Public-IP source contract drifted.'
}
$peerings = @($resources | Where-Object type -eq 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings')
Assert-Contract ($peerings.Count -eq 2) 'Only direct workload/operations peerings are expected.'
$links = @($resources | Where-Object type -eq 'Microsoft.Network/privateDnsZones/virtualNetworkLinks')
Assert-Contract ($links.Count -eq 2) 'Expected private-zone link loops for exactly two VNets.'
$nsg = @($resources | Where-Object type -eq 'Microsoft.Network/networkSecurityGroups')[0]
$rules = $nsg.properties.securityRules
Assert-Contract (@($rules | Where-Object { $_.properties.destinationAddressPrefix -eq 'AzurePlatformDNS' }).Count -eq 0) 'Preserve platform-exempt Azure DNS; its special tag supports Deny and rejects an explicit Allow.'
Assert-Contract (@($rules | Where-Object name -eq 'deny-other-outbound')[0].properties.access -eq 'Deny') 'Default outbound NSG deny is missing.'
$tunnelScript = Get-Content (Join-Path $root 'scripts\Invoke-LabCycle.ps1') -Raw
Assert-Contract ($tunnelScript.Contains('$bastionName = $o.bastionName') -and
    $tunnelScript.Contains('$operationsGroup = $script:LabGroups[2]') -and
    -not $tunnelScript.Contains('bas-csl-hub')) 'Bastion tunnel does not use operations outputs.'
foreach ($scriptName in @('Register-Controller.ps1', 'Set-LabLifecycle.ps1')) {
    $jobScript = Get-Content (Join-Path $root "scripts\$scriptName") -Raw
    Assert-Contract ($jobScript.Contains('parameters = New-LabLifecycleParameters $o')) 'Lifecycle jobs and schedules must share the exact single-parameter context.'
}
$destroy = Get-Content (Join-Path $root 'scripts\Destroy-Lab.ps1') -Raw
Assert-Contract ($destroy.Contains('@($script:LabGroups[1], $script:LabGroups[2], $script:LabGroups[0])')) 'Delete workload, then operations NAT/Bastion, before their network-group public IP dependencies.'
Write-Output 'Firewall-free topology, DNS, NAT, public-IP, NSG and Bastion tunnel contracts passed.'
