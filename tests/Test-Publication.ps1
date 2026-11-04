[CmdletBinding()]
param(
    [string] $WorkspacePath = (Split-Path $PSScriptRoot -Parent),
    [string] $PrivateConfigurationPath,
    [string] $PrivateValuesPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$WorkspacePath = [IO.Path]::GetFullPath($WorkspacePath)
if (-not $PrivateConfigurationPath) { $PrivateConfigurationPath = Join-Path $WorkspacePath '.local\environment.json' }
if (-not $PrivateValuesPath) { $PrivateValuesPath = Join-Path $WorkspacePath '.local\publication-values.json' }
$temporaryGit = Join-Path ([IO.Path]::GetTempPath()) "csl-publication-$([Guid]::NewGuid().ToString('N'))"
$privateValues = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $PrivateConfigurationPath) {
    $context = Get-Content -LiteralPath $PrivateConfigurationPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in @('subscriptionId', 'tenantId', 'expectedAccount', 'azureConfigDirectory')) {
        if ($context.ContainsKey($key) -and $context[$key]) { [void]$privateValues.Add($context[$key]) }
    }
    foreach ($name in $context.resourceGroups.Values) { [void]$privateValues.Add($name) }
}
if (Test-Path -LiteralPath $PrivateValuesPath) {
    foreach ($value in (Get-Content -LiteralPath $PrivateValuesPath -Raw | ConvertFrom-Json)) {
        if ($value) { [void]$privateValues.Add($value) }
    }
}
try {
    & git init --bare --quiet $temporaryGit
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create temporary Git metadata for publication checks.' }
    $gitArgs = @('--git-dir', $temporaryGit, '--work-tree', $WorkspacePath, '-c', 'core.excludesFile=')
    foreach ($path in @('.local/environment.json', '.local/evidence/raw.json', '.azure/deployment-plan.md',
        'config/environment.local.json', 'test.parameters.local.json', 'runner-key', 'private.pem')) {
        & git @gitArgs check-ignore --no-index --quiet -- $path
        if ($LASTEXITCODE -ne 0) { throw "Publication exclusion is missing: $path" }
    }
    $paths = @(& git @gitArgs ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate publication candidates.' }
    if (Test-Path -LiteralPath (Join-Path $WorkspacePath '.git')) {
        $tracked = @(& git -C $WorkspacePath ls-files --cached)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked files.' }
        foreach ($path in $tracked) {
            & git @gitArgs check-ignore --no-index --quiet -- $path
            if ($LASTEXITCODE -eq 0) {
                throw "A private/generated path is already tracked; .gitignore alone does not remove it: $path"
            }
        }
        $paths += $tracked
    }
    $findings = [Collections.Generic.List[string]]::new()
    foreach ($path in ($paths | Sort-Object -Unique)) {
        $absolute = Join-Path $WorkspacePath ($path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
        $bytes = [IO.File]::ReadAllBytes($absolute)
        $content = [Text.Encoding]::UTF8.GetString($bytes)
        foreach ($value in $privateValues) {
            if ($content.IndexOf($value, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $content.IndexOf($value.Replace('\', '\\'), [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $findings.Add("$path (known private environment value)")
                break
            }
        }
        if ($content -match '(?i)/(?:subscriptions|managementGroups)/[0-9a-f]{8}-[0-9a-f-]{27}\b' -or
            $content -match '(?i)[a-z0-9.-]+\.onmicrosoft\.com' -or
            $content -match '(?i)[A-Z]:[\\/]+Users[\\/]+[^\\/\s"<>]+\b' -or
            $content -match '-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----') {
            $findings.Add("$path (tenant/resource identifier, personal path or private key)")
        }
    }
    if ($findings.Count) {
        throw "Publication check failed; values are not printed:`n$($findings -join [Environment]::NewLine)"
    }
    Write-Output "Publication exclusions and known-environment scan passed for $(@($paths | Sort-Object -Unique).Count) candidate files."
} finally {
    if (Test-Path -LiteralPath $temporaryGit) { Remove-Item -LiteralPath $temporaryGit -Recurse -Force }
}
