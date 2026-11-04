$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Shared transport script does not parse.' }
foreach ($name in @('Get-LabSshOptions', 'Wait-LabSsh')) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($definitions.Count -ne 1) { throw 'Expected one production SSH helper.' }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$manifest = @{sshKeyPath = Join-Path ([IO.Path]::GetTempPath()) 'fixture-key'}
$options = @(Get-LabSshOptions $manifest ([IO.Path]::GetTempPath()))
foreach ($required in @('BatchMode=yes', 'ConnectTimeout=20', 'ConnectionAttempts=1',
    'ServerAliveInterval=15', 'ServerAliveCountMax=3', 'StrictHostKeyChecking=accept-new')) {
    if ($required -notin $options) { throw "Missing bounded SSH/SCP setting: $required" }
}
$fixture = @{calls = 0; sleeps = 0; failures = 0; error = ''}
function ssh {
    param([Alias('p')][int] $Port, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    if ($Port -ne 50222 -or $Arguments[-1] -ne 'true') { throw 'Readiness must perform an authenticated SSH command.' }
    $fixture.calls++
    $global:LASTEXITCODE = if ($fixture.calls -le $fixture.failures) { 255 } else { 0 }
    if ($LASTEXITCODE) { $fixture.error }
}
function Start-Sleep([int] $Seconds) { $fixture.sleeps++ }
foreach ($case in @(
    @{failures = 0; error = ''; calls = 1; sleeps = 0; rejected = $false}
    @{failures = 1; error = 'Connection reset'; calls = 2; sleeps = 1; rejected = $false}
    @{failures = 6; error = 'Connection timed out'; calls = 6; sleeps = 5; rejected = $true}
    @{failures = 6; error = 'Permission denied (publickey)'; calls = 1; sleeps = 0; rejected = $true}
    @{failures = 6; error = 'Host key verification failed'; calls = 1; sleeps = 0; rejected = $true}
)) {
    $fixture.calls = 0; $fixture.sleeps = 0
    $fixture.failures = $case.failures; $fixture.error = $case.error
    $rejected = $false
    try { Wait-LabSsh $manifest ([IO.Path]::GetTempPath()) 50222 -WarningAction SilentlyContinue }
    catch { $rejected = $true }
    if ($rejected -ne $case.rejected -or $fixture.calls -ne $case.calls -or $fixture.sleeps -ne $case.sleeps) {
        throw 'SSH readiness accepted a listener-only proxy, retried authentication failure, or exceeded its bounded retries.'
    }
}
$global:LASTEXITCODE = 0
'Authenticated SSH readiness, bounded noninteractive SSH/SCP settings and terminal authentication errors passed.'
