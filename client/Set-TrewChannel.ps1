param(
  [ValidateSet('stable','beta','developer')]
  [string]$Channel
)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'TrewGamesUpdater'
$path=Join-Path $root 'config.json'
if(-not(Test-Path -LiteralPath $path)){throw 'Updater config was not found.'}
$c=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
$c.channel=$Channel
$c|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ("Trew Games update channel is now: "+$Channel) -ForegroundColor Green
