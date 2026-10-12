$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'ci_android_signing.ps1'
$variables = @('RUNNER_TEMP', 'ANDROID_KEYSTORE_BASE64', 'ANDROID_STORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS')
$previous = @{}
foreach ($name in $variables) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('aurora-signing-test-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $env:RUNNER_TEMP = $testRoot
    foreach ($name in $variables | Select-Object -Skip 1) { [Environment]::SetEnvironmentVariable($name, $null) }
    $failed = $false
    try { & $script -Action Prepare } catch { $failed = $_.Exception.Message -match 'Missing required GitHub Actions secrets' }
    if (-not $failed) { throw 'Missing secrets were not rejected.' }
    $env:ANDROID_STORE_PASSWORD = 'fixture-store'
    $env:ANDROID_KEY_PASSWORD = 'fixture-key'
    $env:ANDROID_KEY_ALIAS = 'fixture-alias'
    $env:ANDROID_KEYSTORE_BASE64 = 'invalid-base64!'
    $failed = $false
    try { & $script -Action Prepare } catch { $failed = $_.Exception.Message -eq 'ANDROID_KEYSTORE_BASE64 must contain a valid Base64 keystore.' }
    if (-not $failed) { throw 'Invalid Base64 was not rejected safely.' }
    $env:ANDROID_KEYSTORE_BASE64 = [Convert]::ToBase64String([byte[]](1, 2, 3))
    & $script -Action Prepare
    $path = Join-Path $testRoot 'aurora-signing/release.jks'
    if ([IO.File]::ReadAllBytes($path).Length -ne 3) { throw 'Fixture restoration failed.' }
    $acl = Get-Acl -LiteralPath (Split-Path -Parent $path)
    if (-not $acl.AreAccessRulesProtected -or @($acl.Access).Count -ne 1) { throw 'Signing ACL is not restricted.' }
    & $script -Action Cleanup
    if (Test-Path -LiteralPath (Join-Path $testRoot 'aurora-signing')) { throw 'Cleanup did not remove signing files.' }
    & $script -Action Cleanup
    Write-Output 'Signing checks passed: missing secrets, invalid Base64, restoration, ACL, idempotent cleanup.'
} finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
    # testRoot is created above, has a fixed prefix, and must remain inside TEMP.
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($testRoot))).TrimEnd('\') -ne [IO.Path]::GetTempPath().TrimEnd('\')) {
        throw 'Test cleanup path escaped TEMP.'
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
