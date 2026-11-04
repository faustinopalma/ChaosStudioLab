[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [ValidateSet('BASE-001', 'HA-APP-001', 'HA-APP-ZONE-001', 'HA-DB-001', 'HA-COMBINED-001', 'HA-AZ-001')]
    [string] $TestId = 'BASE-001'
)
throw "BLOCKED: $TestId requires the new Linux App Service/private-SCM/three-zone qualification and native Action effect evaluator. The historical Container Apps test runner is retired; no fault or cleanup was executed."
