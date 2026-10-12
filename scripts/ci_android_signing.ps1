param([Parameter(Mandatory)][ValidateSet('Prepare', 'Cleanup')][string]$Action)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { throw 'RUNNER_TEMP is required.' }
$temporaryRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/')
$signingDirectory = [IO.Path]::GetFullPath((Join-Path $temporaryRoot 'aurora-signing'))
if ((Split-Path -Parent $signingDirectory) -ne $temporaryRoot) {
    throw 'Signing directory must be directly inside RUNNER_TEMP.'
}
if ((Test-Path -LiteralPath $signingDirectory) -and
    ((Get-Item -LiteralPath $signingDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Signing directory cannot be a link.'
}

if ($Action -eq 'Cleanup') {
    if (Test-Path -LiteralPath $signingDirectory) {
        Remove-Item -LiteralPath $signingDirectory -Recurse -Force
    }
    return
}

$required = @('ANDROID_KEYSTORE_BASE64', 'ANDROID_STORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS')
$missing = @($required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) })
if ($missing.Count -gt 0) {
    throw "Missing required GitHub Actions secrets: $($missing -join ', '). Configure Android release signing in repository Settings."
}
try { $keystoreBytes = [Convert]::FromBase64String($env:ANDROID_KEYSTORE_BASE64) }
catch { throw 'ANDROID_KEYSTORE_BASE64 must contain a valid Base64 keystore.' }
if ($keystoreBytes.Length -eq 0) { throw 'ANDROID_KEYSTORE_BASE64 contains an empty keystore.' }
if (Test-Path -LiteralPath $signingDirectory) { throw 'Signing directory already exists; run Cleanup first.' }

New-Item -ItemType Directory -Path $signingDirectory | Out-Null
try {
    $acl = Get-Acl -LiteralPath $signingDirectory
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $signingDirectory -AclObject $acl
    [IO.File]::WriteAllBytes((Join-Path $signingDirectory 'release.jks'), $keystoreBytes)
} catch {
    Remove-Item -LiteralPath $signingDirectory -Recurse -Force
    throw 'Could not restore the release keystore in the protected runner directory.'
} finally {
    [Array]::Clear($keystoreBytes, 0, $keystoreBytes.Length)
}
