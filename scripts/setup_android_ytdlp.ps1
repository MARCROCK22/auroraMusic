[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot '..\tools\android\yt-dlp-res'
}
Add-Type -AssemblyName System.IO.Compression

$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android_ytdlp.lock.json') -Raw | ConvertFrom-Json
if ($lock.repository -ne 'yt-dlp/yt-dlp' -or $lock.version -ne '2026.08.19' -or
    $lock.asset -ne 'yt-dlp' -or $lock.url -ne 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp' -or
    $lock.sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'Invalid Android yt-dlp provenance lock.'
}

$output = [IO.Path]::GetFullPath($OutputDirectory)
$raw = Join-Path $output 'raw'
$resource = Join-Path $raw 'ytdlp'
$licenseDirectory = Join-Path $output '..\licenses'
New-Item -ItemType Directory -Path $raw -Force | Out-Null
$temporary = Join-Path $output ('.yt-dlp-' + [guid]::NewGuid().ToString('N'))
try {
    Invoke-WebRequest -Uri $lock.url -OutFile $temporary -TimeoutSec 600
    $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $lock.sha256) { throw "yt-dlp SHA-256 mismatch: $actual" }
    $bytes = [IO.File]::ReadAllBytes($temporary)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne '#!/u') {
        throw 'Downloaded yt-dlp is not the expected zipimport executable.'
    }
    # The library resource is the Python shebang followed by a ZIP archive.
    $zipOffset = -1
    for ($i = 4; $i -lt [Math]::Min($bytes.Length - 3, 256); $i++) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i + 1] -eq 0x4b -and $bytes[$i + 2] -eq 0x03 -and $bytes[$i + 3] -eq 0x04) { $zipOffset = $i; break }
    }
    if ($zipOffset -lt 0) { throw 'yt-dlp executable does not contain the expected zipimport payload.' }
    $zipStream = [IO.MemoryStream]::new($bytes, $zipOffset, $bytes.Length - $zipOffset, $false)
    try {
        $archive = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if (-not ($archive.Entries | Where-Object FullName -eq '__main__.py')) { throw 'yt-dlp ZIP payload is missing __main__.py.' }
            $ejsVersion = $archive.GetEntry('yt_dlp_ejs/_version.py')
            if (-not $ejsVersion) { throw 'yt-dlp ZIP payload is missing the bundled EJS package.' }
            $versionReader = [IO.StreamReader]::new($ejsVersion.Open())
            try {
                if ($versionReader.ReadToEnd() -notmatch "__version__\s*=\s*version\s*=\s*'0\.8\.0'") {
                    throw 'yt-dlp ZIP payload does not contain the pinned EJS 0.8.0 bundle.'
                }
            } finally { $versionReader.Dispose() }
        } finally { $archive.Dispose() }
    } finally { $zipStream.Dispose() }
    Move-Item -LiteralPath $temporary -Destination $resource -Force

    New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    foreach ($notice in @('LICENSE', 'THIRD_PARTY_LICENSES.txt')) {
        $url = "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$($lock.version)/$notice"
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $licenseDirectory "yt-dlp-$notice") -TimeoutSec 60
    }
    Write-Host "Prepared yt-dlp $($lock.version) for Android (SHA-256 verified)."
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
