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
if ($installer -match 'docker|Automation|powershell_7_4' -or
    -not $installer.Contains('apt-get install -y azure-cli powershell-lts')) {
    throw 'Runner installation retains a retired container/Automation dependency.'
}
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
    $build = $buildAst.Extent.Text
    if (-not $build.Contains('timeout 1200 bash scripts/runner/bootstrap.sh') -or
        -not $build.Contains('if ($LASTEXITCODE -ne 0)') -or
        -not $bootstrap.Contains('az webapp deploy') -or
        -not $bootstrap.Contains('--async false --track-status false') -or
        -not $build.Contains('scripts/runner/verify.ps1') -or
        -not $build.Contains('scripts/runner/qualify-app.ps1 -OutputPath results/publication-participation.json') -or
        -not $bootstrap.Contains('sha256sum --check') -or
        -not $bootstrap.Contains('"$API_FQDN" "$SCM_FQDN"') -or
        $bootstrap -match 'docker|az acr') {
        throw 'Bounded private SCM/checksummed package publication contract drifted.'
    }
} finally {
    $script:LabRoot = $root
    Remove-Item -LiteralPath $fixture -Recurse
}
'Actual archive LF normalization, private SCM package publication, bounded bootstrap, HTTPS package sources, strict TLS and final marker checks passed.'
