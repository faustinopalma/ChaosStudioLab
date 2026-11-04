$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) "csl-native-entrypoint-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts') -Force | Out-Null
Copy-Item (Join-Path $root 'scripts\Test-Lab.ps1') (Join-Path $fixture 'scripts')
Copy-Item (Join-Path $root 'scripts\Lab.Native.ps1') (Join-Path $fixture 'scripts')
@'
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$script:LabRoot=Split-Path $PSScriptRoot -Parent
$script:LabGroups=@('rg-fixture-net','rg-fixture-work','rg-fixture-ops')
function Confirm-LabContext {}
function Read-LabManifest([string]$Path) { Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable }
function Assert-LabPolicyExemptions($Manifest) {}
function Get-LabSshOptions($Manifest,$Root) { @() }
function Write-LabJson([string]$Path,$Value) { $Value | ConvertTo-Json -Depth 30 | Set-Content $Path }
function Invoke-LabAz([string[]]$Arguments) {
    if(($Arguments[0..2] -join ' ') -ne 'postgres flexible-server show') {
        throw 'Unexpected cloud operation while the database is stopped.'
    }
    return '{"state":"Stopped","highAvailability":{"mode":"ZoneRedundant","state":"","standbyAvailabilityZone":"2"},"network":{"publicNetworkAccess":"Disabled"}}'
}
function Invoke-LabArm { throw 'Native control-plane operation attempted despite failed readiness.' }
function Wait-LabSsh { throw 'Private workload attempted despite failed database readiness.' }
'@ | Set-Content (Join-Path $fixture 'scripts\Lab.Common.ps1')
$manifestPath=Join-Path $fixture 'manifest.json'
@{architecture='linux-app-service';outputs=@{'csl-infrastructure'=@{workload=@{value=@{postgresName='fixture'}}}}} |
    ConvertTo-Json -Depth 10 | Set-Content $manifestPath
$prior=$env:CSL_ENVIRONMENT_FILE
$env:CSL_ENVIRONMENT_FILE='fixture-approved-environment'
try {
    foreach($test in @('BASE-001','HA-APP-001','HA-APP-ZONE-001','HA-DB-001','HA-COMBINED-001','HA-AZ-001')) {
        $caught=$false
        try { & (Join-Path $fixture 'scripts\Test-Lab.ps1') -ManifestPath $manifestPath -TestId $test | Out-Null }
        catch { $caught=$_.Exception.Message -like 'BLOCKED:*PostgreSQL state=Stopped*' }
        $directory=Get-ChildItem (Join-Path $fixture 'tests') -Directory -Filter "$test-*" | Select-Object -First 1
        $verdict=Get-Content (Join-Path $directory.FullName 'verdict.json') -Raw | ConvertFrom-Json
        if($verdict.status -ne 'BLOCKED' -or ($test -ne 'HA-AZ-001' -and -not $caught)) {
            throw "$test did not fail closed before private workload or native control operations."
        }
    }
    'Actual native entrypoint blocks all baseline/fault cases on stopped PostgreSQL before SSH/load/injection; real-zone evidence has an independent guard.'
} finally {
    $env:CSL_ENVIRONMENT_FILE=$prior
    Remove-Item -LiteralPath $fixture -Recurse
}
