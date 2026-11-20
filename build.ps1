<#
.SYNOPSIS
  Packages the addon (the repo root's TOC, Lua files and LICENSE) into
  dist/OmniCast_Forever (ready to copy into Interface\AddOns) and
  dist/OmniCast_Forever-v<version>.zip. CurseForge builds its own package
  from tags using .pkgmeta; this script is for local builds.

.EXAMPLE
  ./build.ps1                 # check + package current version
  ./build.ps1 -Bump patch     # 0.1.0 -> 0.1.1, then package
  ./build.ps1 -Bump minor     # 0.1.3 -> 0.2.0, then package
  ./build.ps1 -Install        # also copy into the WoW Forever AddOns folder
#>
param(
    [ValidateSet("", "patch", "minor")]
    [string]$Bump = "",
    [switch]$Install,
    [switch]$SkipCheck,
    [string]$AddOnsDir = $(if ($env:WOW_FOREVER_ADDONS) { $env:WOW_FOREVER_ADDONS } else { "D:\Battlenet\World of Warcraft\_forever_\Interface\AddOns" })
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$name = "OmniCast_Forever"
$toc = Join-Path $root "$name.toc"

# --- version -----------------------------------------------------------------
$tocText = Get-Content $toc -Raw
if ($tocText -notmatch '(?m)^## Version:\s*(\d+)\.(\d+)\.(\d+)') { throw "No '## Version: x.y.z' in $toc" }
$major, $minor, $patch = [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]
if ($Bump -eq "patch") { $patch++ }
if ($Bump -eq "minor") { $minor++; $patch = 0 }
$version = "$major.$minor.$patch"
if ($Bump) {
    $tocText = $tocText -replace '(?m)^## Version:.*$', "## Version: $version"
    [IO.File]::WriteAllText($toc, $tocText)
    Write-Host "Version bumped to $version"
}

# --- syntax check ------------------------------------------------------------
if (-not $SkipCheck) {
    if (-not (Test-Path (Join-Path $root "node_modules\luaparse"))) {
        Push-Location $root; npm install --silent | Out-Null; Pop-Location
    }
    node (Join-Path $root "tools\check-lua.mjs")
    if ($LASTEXITCODE -ne 0) { throw "Lua check failed" }
}

# --- package -----------------------------------------------------------------
$dist = Join-Path $root "dist"
New-Item -ItemType Directory $dist -Force | Out-Null
$out = Join-Path $dist $name
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory $out | Out-Null
Copy-Item (Join-Path $root "$name.toc"), (Join-Path $root "*.lua"), (Join-Path $root "LICENSE") $out

$zip = Join-Path $dist "$name-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $out -DestinationPath $zip
Write-Host "Packaged v$version -> $out"
Write-Host "Zip            -> $zip"

# --- optional install ------------------------------------------------------------
if ($Install) {
    if (-not (Test-Path $AddOnsDir)) { throw "AddOns folder not found: $AddOnsDir" }
    $dest = Join-Path $AddOnsDir $name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $out $dest -Recurse
    Write-Host "Installed      -> $dest  (restart the game client if the addon is new; /reload otherwise)"
}
