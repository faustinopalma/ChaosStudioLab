$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bash = if ($IsWindows) {
    Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
} else { (Get-Command bash -ErrorAction Stop).Source }
if (-not (Test-Path -LiteralPath $bash)) { throw 'Existing Bash is required to validate the Linux bootstrap scripts.' }
$installerPath = Join-Path $root 'scripts\runner\install.sh'
$installer = Get-Content -LiteralPath $installerPath -Raw
foreach ($path in @($installerPath, (Join-Path $root 'scripts\runner\bootstrap.sh'))) {
    & $bash -n $path
    if ($LASTEXITCODE) { throw "Invalid Bash syntax: $path" }
}
$rewrite = @($installer -split '\r?\n' | Where-Object { $_.StartsWith('sed -i -E ') })
if ($rewrite.Count -ne 1) { throw 'Expected one source package-repository rewrite.' }
$command = $rewrite[0] -replace '^sed -i -E ', 'sed -E ' -replace ' /etc/apt/sources.list$', ''
$actual = @(
    'deb http://azure.archive.ubuntu.com/ubuntu jammy main'
    'deb http://archive.ubuntu.com/ubuntu jammy-updates main'
    'deb http://security.ubuntu.com/ubuntu jammy-security main'
    'deb https://azure.archive.ubuntu.com/ubuntu jammy-security main'
    'deb http://example.invalid/ubuntu jammy main'
) | & $bash -c $command
if ($LASTEXITCODE) { throw 'The actual installer sed expression failed.' }
$expected = @(
    'deb https://archive.ubuntu.com/ubuntu jammy main'
    'deb https://archive.ubuntu.com/ubuntu jammy-updates main'
    'deb https://security.ubuntu.com/ubuntu jammy-security main'
    'deb https://archive.ubuntu.com/ubuntu jammy-security main'
    'deb http://example.invalid/ubuntu jammy main'
)
if (($actual -join "`n").Trim() -cne ($expected -join "`n")) { throw 'Package-source rewriting changed the wrong host or failed to enable HTTPS.' }
$repeated = $actual | & $bash -c $command
if ($LASTEXITCODE -or ($repeated -join "`n").Trim() -cne ($expected -join "`n")) { throw 'Package-source rewriting is not idempotent.' }
if (@([regex]::Matches($installer, 'apt-get -o APT::Update::Error-Mode=any update')).Count -ne 2) {
    throw 'Both package-index updates must fail explicitly on any repository error.'
}
if ($installer -notmatch "awk '(?<selection>[^']+)'") { throw 'PowerShell package-selection expression was not found.' }
$selection = "awk '$($Matches.selection)'"
$package = @(
    'powershell-lts | 7.6.1-1.deb | https://example.invalid'
    'powershell-lts | 7.4.13-1.deb | https://example.invalid'
    'powershell-lts | 7.4.12-1.deb | https://example.invalid'
) | & $bash -c $selection
if ($LASTEXITCODE -or $package.Trim() -ne '7.4.13-1.deb') { throw 'The installer selected a different PowerShell runtime.' }
$unsupported = 'powershell-lts | 7.6.1-1.deb | https://example.invalid' | & $bash -c $selection
if ($LASTEXITCODE -or -not [string]::IsNullOrWhiteSpace($unsupported)) { throw 'Unsupported PowerShell versions must not be selected.' }
$marker = '(?m)^CSL_INSTALL_COMPLETED\r?$'
if (-not $installer.TrimEnd().EndsWith("printf '\nCSL_INSTALL_COMPLETED\n'") -or
    -not (Get-Content (Join-Path $root 'scripts\Lab.Common.ps1') -Raw).Contains($marker) -or
    "k6 v1.5.0`ndocker failed" -match $marker -or
    'CSL_INSTALL_COMPLETED-extra' -match $marker -or
    "k6 v1.5.0`nCSL_INSTALL_COMPLETED`r`n" -notmatch $marker) {
    throw 'Only the terminal completed-install marker may establish software initialization success.'
}
$bootstrap = Get-Content (Join-Path $root 'scripts\runner\bootstrap.sh') -Raw
if (-not $bootstrap.Contains('PGSSLMODE=verify-full') -or
    -not $bootstrap.Contains('PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt')) {
    throw 'Private PostgreSQL bootstrap must retain hostname verification and the system CA bundle.'
}
$tokens = $null
$errors = $null
$buildAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\Build-Lab.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Runner build script does not parse.' }
$archiveLoops = @($buildAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and
        $node.Variable.VariablePath.UserPath -eq 'file' -and $node.Condition.Extent.Text -eq '$entries'
}, $true))
if ($archiveLoops.Count -ne 1) { throw 'Expected one source-archive file loop.' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-archive-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $script:LabRoot = $fixture
    [IO.File]::WriteAllText((Join-Path $fixture 'fixture.sh'), "set -euo pipefail`r`nprintf 'CSL_ARCHIVE_LF\n'`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'fixture.bin'), [byte[]](0..255))
    $entries = @(Get-Item (Join-Path $fixture 'fixture.sh'), (Join-Path $fixture 'fixture.bin'))
    $archive = Join-Path $fixture 'source.zip'
    $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
    try { & ([scriptblock]::Create($archiveLoops[0].Extent.Text)) } finally { $zip.Dispose() }
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $reader = [IO.StreamReader]::new($zip.GetEntry('fixture.sh').Open())
        try { $shellText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($shellText.Contains("`r")) { throw 'The actual archive contains CRLF shell content.' }
        $actual = & $bash -c $shellText
        if ($LASTEXITCODE -or $actual -ne 'CSL_ARCHIVE_LF') { throw 'The archived shell content does not execute correctly.' }
        $stream = $zip.GetEntry('fixture.bin').Open()
        $bytes = [IO.MemoryStream]::new()
        try { $stream.CopyTo($bytes) } finally { $stream.Dispose() }
        try {
            if ([Convert]::ToHexString($bytes.ToArray()) -ne [Convert]::ToHexString([byte[]](0..255))) {
                throw 'Runner packaging changed a nonshell file.'
            }
        } finally { $bytes.Dispose() }
    } finally { $zip.Dispose() }
    $retryLoops = @($buildAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.ForStatementAst] -and
            $node.Condition.Extent.Text -eq '$attempt -le 6'
    }, $true))
    $failureGuards = @($buildAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
            $node.Clauses[0].Item1.Extent.Text -eq '-not $bootstrapSucceeded'
    }, $true))
    if ($retryLoops.Count -ne 1 -or $failureGuards.Count -ne 1) { throw 'Expected one bounded bootstrap loop and explicit success guard.' }
    $retryCode = [scriptblock]::Create($retryLoops[0].Extent.Text + "`n" + $failureGuards[0].Extent.Text)
    & {
        $WarningPreference = 'SilentlyContinue'
        $stateRoot = $fixture
        $sshArgs = @()
        function ssh {
            param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
            if ($Arguments[-1] -eq 'tail -n 100 ~/csl/bootstrap.log') {
                $global:LASTEXITCODE = 0
                return $script:bootstrapCase.log
            }
            $script:bootstrapCalls++
            $global:LASTEXITCODE = if ($script:bootstrapCalls -le $script:bootstrapCase.failures) { 1 } else { 0 }
        }
        function Start-Sleep([int] $Seconds) { $script:bootstrapSleeps++ }
        foreach ($script:bootstrapCase in @(
            @{failures = 0; log = ''; calls = 1; sleeps = 0; rejected = $false}
            @{failures = 1; log = 'Forbidden: role is propagating'; calls = 2; sleeps = 1; rejected = $false}
            @{failures = 6; log = 'Forbidden'; calls = 6; sleeps = 5; rejected = $true}
            @{failures = 6; log = 'set: pipefail: invalid option name'; calls = 1; sleeps = 0; rejected = $true}
        )) {
            $script:bootstrapCalls = 0
            $script:bootstrapSleeps = 0
            $bootstrapSucceeded = $false
            $rejected = $false
            try { . $retryCode } catch { $rejected = $true }
            if ($rejected -ne $script:bootstrapCase.rejected -or
                $script:bootstrapCalls -ne $script:bootstrapCase.calls -or
                $script:bootstrapSleeps -ne $script:bootstrapCase.sleeps) {
                throw 'Actual bootstrap retry behavior differs from the authorization-only bounded contract.'
            }
        }
    }
} finally {
    $script:LabRoot = $root
    Remove-Item -LiteralPath $fixture -Recurse
}
'Actual archive LF normalization, bounded authorization retries, sed/awk, supported runtime, strict TLS and final marker checks passed.'
