[CmdletBinding()]
param([string]$SdkDirectory = '', [string]$OriginalAar = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $SdkDirectory) { $SdkDirectory = Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$work = Join-Path $project 'tools/android/webp'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$sourceUrl = 'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz'
$sourceHash = 'E4AB7009BF0629FD11982D4C2AA83964CF244CFFBA7347ECD39019A9E38C4564'
$aarHash = '0A87FFA6CF912B0FE76C1A99B9107F543EE2F247935FAE2C71F0822EB7BC5F49'
# Hashes are recorded from the downloaded official source archive and Maven AAR.
# Rebuild the libraries; never rewrite ELF alignment fields in existing binaries.
$archive = Join-Path $work 'libwebp-1.6.0.tar.gz'
if (-not (Test-Path -LiteralPath $archive)) { Invoke-WebRequest -UseBasicParsing $sourceUrl -OutFile $archive }
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sourceHash) { throw 'WebP source SHA256 mismatch.' }
if (-not $OriginalAar) {
    $cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/io.github.junkfood02.youtubedl-android/ffmpeg/0.18.1'
    $cached = Get-ChildItem -LiteralPath $cache -Filter '*.aar' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cached) { $OriginalAar = $cached.FullName } else {
        $OriginalAar = Join-Path $work 'ffmpeg-original-0.18.1.aar'
        Invoke-WebRequest -UseBasicParsing 'https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/ffmpeg/0.18.1/ffmpeg-0.18.1.aar' -OutFile $OriginalAar
    }
}
if ((Get-FileHash -LiteralPath $OriginalAar -Algorithm SHA256).Hash -ne $aarHash) { throw 'Original FFmpeg AAR SHA256 mismatch.' }
$source = Join-Path $work 'libwebp-1.6.0'
if (-not (Test-Path -LiteralPath (Join-Path $source 'CMakeLists.txt'))) {
    & tar -xf $archive -C $work
    if ($LASTEXITCODE -ne 0) { throw 'WebP extraction failed.' }
}
$cmakeRoot = Join-Path $SdkDirectory 'cmake/3.22.1/bin'
$cmake = Join-Path $cmakeRoot 'cmake.exe'
$ndkRoot = Join-Path $SdkDirectory 'ndk/28.2.13676358'
$nativeBin = Join-Path $ndkRoot 'toolchains/llvm/prebuilt/windows-x86_64/bin'
$readelf = Join-Path $nativeBin 'llvm-readelf.exe'
$strip = Join-Path $nativeBin 'llvm-strip.exe'
foreach ($required in @($cmake,$readelf,$strip)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required SDK tool missing: $required" } }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Restore-UnixZipMetadata([string]$Path) {
    # ZipArchive.Update resets the creator OS to Windows even for unchanged
    # entries. Restore Unix metadata so Commons Compress recognizes symlinks.
    # This modifies ZIP headers only; no ELF executable bytes are altered.
    $bytes = [IO.File]::ReadAllBytes($Path)
    $eocd = -1
    for ($index = $bytes.Length - 22; $index -ge [Math]::Max(0,$bytes.Length - 65557); $index--) {
        if ([BitConverter]::ToUInt32($bytes,$index) -eq 0x06054b50) { $eocd=$index; break }
    }
    if ($eocd -lt 0) { throw 'ZIP end record missing.' }
    $count = [BitConverter]::ToUInt16($bytes,$eocd+10)
    $offset = [int][BitConverter]::ToUInt32($bytes,$eocd+16)
    for ($entryIndex=0; $entryIndex -lt $count; $entryIndex++) {
        if ([BitConverter]::ToUInt32($bytes,$offset) -ne 0x02014b50) { throw 'Invalid ZIP central directory.' }
        $mode = [BitConverter]::ToUInt32($bytes,$offset+38) -shr 16
        if ($mode -ne 0) { $bytes[$offset+5] = 3 }
        $offset += 46 + [BitConverter]::ToUInt16($bytes,$offset+28) + [BitConverter]::ToUInt16($bytes,$offset+30) + [BitConverter]::ToUInt16($bytes,$offset+32)
    }
    [IO.File]::WriteAllBytes($Path,$bytes)
}
$output = Join-Path $project 'tools/android/ffmpeg-0.18.1-webp16kb.aar'
$staging = Join-Path $work ('ffmpeg-' + [guid]::NewGuid().ToString('N') + '.aar')
Copy-Item -LiteralPath $OriginalAar -Destination $staging
$names = @('libsharpyuv.so','libwebp.so','libwebpdecoder.so','libwebpdemux.so','libwebpmux.so')
$manifest = @()
$aar = [IO.Compression.ZipFile]::Open($staging,[IO.Compression.ZipArchiveMode]::Update)
try {
    foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64','x86')) {
        $build = Join-Path $work ('build-' + $abi)
        $options = @('-S',$source,'-B',$build,'-G','Ninja',"-DCMAKE_MAKE_PROGRAM=$(Join-Path $cmakeRoot 'ninja.exe')", "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $ndkRoot 'build/cmake/android.toolchain.cmake')", "-DANDROID_ABI=$abi", '-DANDROID_PLATFORM=android-24', '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384', '-DBUILD_SHARED_LIBS=ON','-DCMAKE_BUILD_TYPE=Release')
        foreach ($option in @('CWEBP','DWEBP','GIF2WEBP','IMG2WEBP','VWEBP','WEBPINFO','ANIM_UTILS','EXTRAS','WEBPMUX')) { $options += "-DWEBP_BUILD_$option=OFF" }
        $options += '-DWEBP_BUILD_LIBWEBPMUX=ON'
        & $cmake @options
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $abi" }
        & $cmake --build $build --parallel 4
        if ($LASTEXITCODE -ne 0) { throw "WebP compile failed for $abi" }
        $payloadPath = Join-Path $work ("ffmpeg-$abi.zip")
        $aarEntryPath = "jni/$abi/libffmpeg.zip.so"
        $aarEntry = $aar.GetEntry($aarEntryPath)
        if (-not $aarEntry) { throw "AAR payload missing: $aarEntryPath" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($aarEntry,$payloadPath,$true)
        $payload = [IO.Compression.ZipFile]::Open($payloadPath,[IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($name in $names) {
                $built = Get-ChildItem -LiteralPath $build -Recurse -File -Filter $name | Select-Object -First 1
                if (-not $built) { throw "Compiled library missing: $abi/$name" }
                & $strip --strip-unneeded $built.FullName
                if ($LASTEXITCODE -ne 0) { throw "Strip failed: $name" }
                $headers = @(& $readelf -lW $built.FullName)
                if ($LASTEXITCODE -ne 0) { throw "Invalid ELF: $name" }
                foreach ($load in @($headers | Where-Object { $_ -match '^\s+LOAD\s' })) {
                    if ([Convert]::ToInt64(($load.Trim() -split '\s+')[-1].Replace('0x',''),16) -lt 16384) { throw "Rebuilt ELF alignment invalid: $abi/$name" }
                }
                $dynamic = @(& $readelf -dW $built.FullName)
                if (-not ($dynamic -match "SONAME.*\[$([regex]::Escape($name))\]")) { throw "Rebuilt SONAME mismatch: $abi/$name" }
                $entryPath = "usr/lib/$name"
                $old = $payload.GetEntry($entryPath)
                if (-not $old) { throw "Original FFmpeg library missing: $entryPath" }
                $originalPath = Join-Path $work ("original-$abi-$name")
                [IO.Compression.ZipFileExtensions]::ExtractToFile($old,$originalPath,$true)
                $originalDynamic = @(& $readelf -dW $originalPath)
                if (-not ($originalDynamic -match "SONAME.*\[$([regex]::Escape($name))\]")) { throw "Original SONAME mismatch: $abi/$name" }
                $originalSymbols = @(& $readelf --dyn-syms -W $originalPath | Where-Object { $_ -match '\sGLOBAL\s+DEFAULT\s+(?!UND\s)\S+\s+\S+' } | ForEach-Object { ($_.Trim() -split '\s+')[-1] })
                $newSymbols = @(& $readelf --dyn-syms -W $built.FullName | Where-Object { $_ -match '\sGLOBAL\s+DEFAULT\s+(?!UND\s)\S+\s+\S+' } | ForEach-Object { ($_.Trim() -split '\s+')[-1] })
                $missingSymbols = @($originalSymbols | Where-Object { $_ -notin $newSymbols })
                if ($missingSymbols.Count) { throw "Removed public ELF symbols in $abi/$name : $($missingSymbols -join ', ')" }
                $old.Delete()
                $entry = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($payload,$built.FullName,$entryPath,[IO.Compression.CompressionLevel]::Optimal)
                $entry.ExternalAttributes = 0x1ED0000
                $manifest += @{ abi=$abi; library=$name; sha256=(Get-FileHash -LiteralPath $built.FullName -Algorithm SHA256).Hash }
            }
        } finally { $payload.Dispose() }
        Restore-UnixZipMetadata $payloadPath
        $aarEntry.Delete()
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($aar,$payloadPath,$aarEntryPath,[IO.Compression.CompressionLevel]::Optimal)
    }
    foreach ($notice in @('COPYING','PATENTS','AUTHORS')) {
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($aar,(Join-Path $source $notice),"META-INF/webp-1.6.0/$notice")
    }
} finally { $aar.Dispose() }
Copy-Item -LiteralPath $staging -Destination $output -Force
$noticeDirectory = Join-Path $project 'tools/android/licenses/webp-1.6.0'
New-Item -ItemType Directory -Path $noticeDirectory -Force | Out-Null
foreach ($notice in @('COPYING','PATENTS','AUTHORS')) {
    Copy-Item -LiteralPath (Join-Path $source $notice) -Destination (Join-Path $noticeDirectory $notice) -Force
}
@{source=$sourceUrl; sourceSha256=$sourceHash; originalAarSha256=$aarHash; outputSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash; ndk='28.2.13676358'; cmake='3.22.1'; upstreamIssue='https://github.com/yausername/youtubedl-android/issues/365'; libraries=$manifest} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $project 'tools/android/ffmpeg-webp16kb.lock.json') -Encoding utf8
Write-Host "Rebuilt source libraries and verified ELF16KB: $output"
