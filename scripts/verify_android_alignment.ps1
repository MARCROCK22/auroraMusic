[CmdletBinding()]
param([string]$Apk = '', [string]$NativeDirectory = '', [string]$SdkDirectory = '')
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $SdkDirectory) { $SdkDirectory = Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$buildTools = Get-ChildItem -LiteralPath (Join-Path $SdkDirectory 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$ndk = Get-ChildItem -LiteralPath (Join-Path $SdkDirectory 'ndk') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$readelf = Join-Path $ndk.FullName 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe'
$zipalign = Join-Path $buildTools.FullName 'zipalign.exe'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tempRoot = [IO.Path]::GetFullPath((Join-Path $project ('build/alignment-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
function Expand-NativeEntries([string]$Archive, [string]$Destination, [string]$Pattern) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notmatch $Pattern) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith([IO.Path]::GetFullPath($Destination) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Entrada nativa fuera del destino.' }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    } finally { $zip.Dispose() }
}
try {
    if (-not $NativeDirectory) {
        if (-not $Apk) { $Apk = Join-Path $project 'build/app/outputs/flutter-apk/app-debug.apk' }
        & $zipalign -c -P 16 4 $Apk
        if ($LASTEXITCODE -ne 0) { throw 'El APK no cumple alineación ZIP de 16 KB.' }
        $NativeDirectory = Join-Path $tempRoot 'apk'
        New-Item -ItemType Directory -Path $NativeDirectory | Out-Null
        Expand-NativeEntries $Apk $NativeDirectory '^lib/arm64-v8a/.*\.so$'
    }
    $libraries = @(Get-ChildItem -LiteralPath $NativeDirectory -File -Recurse | Where-Object { $_.Name -match '\.so(?:\.\d+)*$' -and $_.FullName -notmatch '[\\/]x86' })
    if ($libraries.Count -eq 0) { throw 'No hay bibliotecas ARM64 para verificar. Usa un APK --target-platform android-arm64.' }
    foreach ($archive in @($libraries | Where-Object { $_.Name -match '\.zip\.so$' })) {
        $expanded = Join-Path $tempRoot $archive.Name
        New-Item -ItemType Directory -Path $expanded | Out-Null
        Expand-NativeEntries $archive.FullName $expanded '\.so(?:\.\d+)*$'
        $libraries += @(Get-ChildItem -LiteralPath $expanded -Recurse -File)
    }
    $checked = 0
    $failures = @()
    foreach ($library in ($libraries | Where-Object { $_.Name -notmatch '\.zip\.so$' })) {
        $stream = [IO.File]::OpenRead($library.FullName)
        $magic = New-Object byte[] 4
        try { $null = $stream.Read($magic,0,4) } finally { $stream.Dispose() }
        if ($magic[0] -ne 127 -or $magic[1] -ne 69 -or $magic[2] -ne 76 -or $magic[3] -ne 70) {
            # ZIP stores Unix symlinks as the relative target filename.
            if ($library.Length -lt 512) {
                $linkTarget = [IO.Path]::GetFullPath((Join-Path $library.DirectoryName ([IO.File]::ReadAllText($library.FullName).Trim())))
                if ($linkTarget.StartsWith($library.DirectoryName + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $linkTarget)) { continue }
            }
            throw "Archivo nativo no reconocido: $($library.Name)"
        }
        $headers = @(& $readelf -lW $library.FullName 2>$null)
        if ($LASTEXITCODE -ne 0) { throw "Archivo nativo no reconocido: $($library.Name)" }
        $loads = @($headers | Where-Object { $_ -match '^\s+LOAD\s' })
        if ($loads.Count -eq 0) { throw "Sin segmentos ELF LOAD: $($library.Name)" }
        foreach ($load in $loads) {
            $alignment = ($load.Trim() -split '\s+')[-1]
            if ([Convert]::ToInt64($alignment.Replace('0x',''),16) -lt 16384) { $failures += "$($library.Name): $alignment" }
        }
        $checked++
    }
    $failures = @($failures | Sort-Object -Unique)
    $reportDirectory = Join-Path $project 'build/validation'
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    @{ nativeDirectory = $NativeDirectory; apk = $Apk; elfChecked = $checked; failures = $failures } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $reportDirectory 'android-alignment.json') -Encoding utf8
    if ($failures.Count) { throw ('Alineaciones ELF incompatibles con 16 KB: ' + ($failures -join ', ')) }
    Write-Host "PASS: $checked ELF ARM64 con segmentos LOAD >= 16 KB (incluye dependencias Python/FFmpeg empaquetadas)."
    Write-Host 'La alineación estática no sustituye una prueba en un dispositivo Android de páginas 16 KB.'
} finally {
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $project 'build'))
    if (-not $tempRoot.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta temporal fuera de build.' }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
