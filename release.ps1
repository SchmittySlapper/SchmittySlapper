# Publishes a new version: stamps the version into the TOC files, commits, tags,
# pushes, zips each addon on its own and creates the GitHub release with both
# zips attached. The two addons are standalone: friends install either or both.
# Each zip also carries the shared SchmittySlapperEditMode helper folder.
# Usage: .\release.ps1 1.0.1
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"
$Version = $Version.TrimStart("v")
$tag = "v$Version"
$root = $PSScriptRoot
$addons = "SchmittySlapperTracker", "SchmittySlapperGrave"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { $gh = $gh.Source }
elseif (Test-Path "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe") { $gh = "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe" }
else { throw "GitHub CLI not found. Install it or sign in with: gh auth login" }

foreach ($name in $addons) {
  $toc = Join-Path $root "$name\$name.toc"
  $lines = (Get-Content $toc) -replace '^## Version: .*', "## Version: $Version"
  [IO.File]::WriteAllLines($toc, $lines)
}

git -C $root add -A
git -C $root commit -q -m "Release $tag"
if ($LASTEXITCODE -ne 0) { Write-Host "nothing new to commit" }
git -C $root tag $tag
git -C $root push origin main
git -C $root push origin $tag

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zips = @()

# one zip per addon
foreach ($name in $addons) {
  $zip = Join-Path $dist "$name-$tag.zip"
  if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path (Join-Path $root $name), (Join-Path $root "SchmittySlapperEditMode") -DestinationPath $zip
  $zips += $zip
}

& $gh release create $tag @zips --title "Schmitty Slapper $tag" --generate-notes
Write-Host "Released $tag with $($zips.Count) zips"
