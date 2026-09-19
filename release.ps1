# Publishes a new version: stamps the version into both TOC files, commits, tags,
# pushes, zips both addon folders and creates the GitHub release.
# Usage: .\release.ps1 1.0.1
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"
$Version = $Version.TrimStart("v")
$tag = "v$Version"
$root = $PSScriptRoot
$addons = "SchmittySlapperTracker", "SchmittySlapperCasts"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { $gh = $gh.Source }
elseif (Test-Path "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe") { $gh = "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe" }
else { throw "GitHub CLI not found. Install it or sign in with: gh auth login" }

foreach ($a in $addons) {
  $toc = Join-Path $root "$a\$a.toc"
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
$zip = Join-Path $dist "SchmittySlapper-$tag.zip"
if (Test-Path $zip) { Remove-Item $zip }
$paths = $addons | ForEach-Object { Join-Path $root $_ }
Compress-Archive -Path $paths -DestinationPath $zip

& $gh release create $tag $zip --title "Schmitty Slapper $tag" --generate-notes
Write-Host "Released $tag"
