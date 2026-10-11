param([string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($ProjectDirectory)
$plugins = Get-Content -LiteralPath (Join-Path $projectRoot '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$linkRoot = Join-Path $projectRoot 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
foreach ($plugin in $plugins.plugins.windows) {
    $linkPath = Join-Path $linkRoot $plugin.name
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
    }
}
Write-Output 'Windows plugin junctions prepared. Build with flutter build windows --no-pub.'
