$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$packageConfig = Get-Content (Join-Path $repoRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$package = $packageConfig.packages | Where-Object name -eq 'flutter_soloud' | Select-Object -First 1
if (-not $package) { throw 'flutter_soloud is missing; run flutter pub get first.' }
$pluginRoot = [Uri]::new($package.rootUri).LocalPath
$pluginRoot = $pluginRoot.Replace('\', '/')
$manifest = Get-Content (Join-Path $pluginRoot 'pubspec.yaml') -Raw
if ($manifest -notmatch '(?m)^version:\s*3\.5\.4\s*$') {
    throw "Expected pinned flutter_soloud 3.5.4 at $pluginRoot"
}

$sdkCmake = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android/Sdk/cmake/*/bin/cmake.exe') |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $sdkCmake) { throw 'CMake from the Android SDK is required for this offline regression.' }
$cmake = $sdkCmake.FullName
$patch = Join-Path $repoRoot 'scripts/patch_flutter_soloud.cmake'
$source = Join-Path $repoRoot 'test/native_so_loud'
$build = Join-Path ([IO.Path]::GetTempPath()) "aurora-soloud-pcm-$([guid]::NewGuid().ToString('N'))"

try {
    & $cmake "-DFLUTTER_SOLOUD_ROOT=$pluginRoot" -P $patch
    if ($LASTEXITCODE -ne 0) { throw 'Pinned flutter_soloud patch validation failed.' }

    & $cmake -S $source -B $build -G 'Visual Studio 17 2022' -A x64 "-DSOLOUD_ROOT=$pluginRoot/src/soloud"
    if ($LASTEXITCODE -ne 0) { throw 'Offline SoLoud regression configure failed.' }
    & $cmake --build $build --config Release --target audio_pcm_regression
    if ($LASTEXITCODE -ne 0) { throw 'Offline SoLoud regression build failed.' }
    & (Join-Path $build 'Release/audio_pcm_regression.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Offline SoLoud PCM regression failed.' }
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedBuild = [IO.Path]::GetFullPath($build)
    if ($resolvedBuild.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedBuild -Recurse -Force -ErrorAction SilentlyContinue
    }
}
