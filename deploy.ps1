# Copies both addons from this repository into the WoW: Forever beta AddOns folder.
# Usage: .\deploy.ps1            (default beta path)
#        .\deploy.ps1 -AddOns "D:\Games\World of Warcraft\_classic_\Interface\AddOns"
param(
  [string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
)

if (-not (Test-Path $AddOns)) {
  Write-Error "AddOns folder not found: $AddOns"
  exit 1
}

foreach ($name in "SchmittySlapperTracker", "SchmittySlapperCasts") {
  $src = Join-Path $PSScriptRoot $name
  $dst = Join-Path $AddOns $name
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  Copy-Item -Recurse $src $dst
  Write-Host "deployed $name -> $dst"
}

Write-Host "Lua changes: /reload in game. New texture files: restart the game."
