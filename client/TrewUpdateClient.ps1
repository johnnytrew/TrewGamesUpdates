param(
  [ValidateSet('Check','Launch','Repair','Status','Update')]
  [string]$Mode='Check',
  [switch]$Quiet
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2

$ClientVersion='1.3.0'
$UpdaterRoot=Join-Path $env:LOCALAPPDATA 'TrewGamesUpdater'
$ConfigPath=Join-Path $UpdaterRoot 'config.json'
$GameRoot=Join-Path $env:LOCALAPPDATA 'Bripardy\games\Connectopoly'
$GameExe=Join-Path $GameRoot 'Connectopoly.exe'
$VersionPath=Join-Path $GameRoot 'TREW_VERSION.json'
$StatusPath=Join-Path $UpdaterRoot 'status.json'
$BackupRoot=Join-Path $env:LOCALAPPDATA 'TrewGamesBackups\AutoUpdates'
$LogPath=Join-Path $UpdaterRoot 'updater.log'
$HubRoot=Join-Path $env:LOCALAPPDATA 'Bripardy'
$HubPath=Join-Path $HubRoot 'Trew Games Hub.hta'
$PendingHubPayload=Join-Path $GameRoot 'TREW_HUB_UPDATE.hta'

New-Item -ItemType Directory -Path $UpdaterRoot -Force | Out-Null
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

function Log([string]$Text){
  try{Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Text)}catch{}
}
function Notify([string]$Text,[string]$Title='Trew Games Updater'){
  if($Quiet){return}
  try{
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show($Text,$Title,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null
  }catch{Write-Host $Text}
}
function Write-Status([string]$State,[string]$Message,[string]$Version=''){
  try{
    [pscustomobject]@{
      state=$State;message=$Message;version=$Version;
      time=(Get-Date).ToUniversalTime().ToString('o')
    }|ConvertTo-Json|Set-Content -LiteralPath $StatusPath -Encoding UTF8
  }catch{}
}
function Get-Config(){
  if(-not(Test-Path -LiteralPath $ConfigPath)){throw 'Trew Games Updater is not configured on this PC.'}
  return Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
}
function Normalize-Version([string]$v){
  $m=[regex]::Match(($v+''),'(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')
  if(-not$m.Success){return [version]'0.0.0.0'}
  $rev=0
  if($m.Groups[4].Success){$rev=[int]$m.Groups[4].Value}
  return New-Object version ([int]$m.Groups[1].Value),([int]$m.Groups[2].Value),([int]$m.Groups[3].Value),$rev
}
function Get-LocalVersion(){
  try{
    if(Test-Path -LiteralPath $VersionPath){
      $v=(Get-Content -LiteralPath $VersionPath -Raw|ConvertFrom-Json).version
      if($v){return [string]$v}
    }
  }catch{}
  try{
    if(Test-Path -LiteralPath $GameExe){
      $v=(Get-Item -LiteralPath $GameExe).VersionInfo.FileVersion
      if($v){return [string]$v}
    }
  }catch{}
  return '0.0.0'
}
function Get-Manifest($cfg){
  $channel=([string]$cfg.channel).ToLowerInvariant()
  if($channel -notin @('stable','beta','developer')){$channel='stable'}
  $base=([string]$cfg.manifestBaseUrl).TrimEnd('/')
  $uri=$base+'/'+$channel+'/manifest.json?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  Log ('Fetching manifest '+$uri)
  return Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 20
}
function Test-GameRunning(){
  try{
    $full=[IO.Path]::GetFullPath($GameExe)
    foreach($p in Get-Process -Name Connectopoly -ErrorAction SilentlyContinue){
      try{
        if($p.Path -and [IO.Path]::GetFullPath($p.Path)-eq$full){return $true}
      }catch{}
    }
  }catch{}
  return $false
}
function Backup-Game([string]$OldVersion){
  $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
  $dest=Join-Path $BackupRoot ("Connectopoly_{0}_{1}" -f ($OldVersion -replace '[^\w\.-]','_'),$stamp)
  New-Item -ItemType Directory -Path $dest -Force|Out-Null
  $args=@(
    $GameRoot,$dest,'/E','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP',
    '/XD',(Join-Path $GameRoot 'backups'),(Join-Path $GameRoot 'desktop-runtime'),(Join-Path $GameRoot 'node_modules'),
    '/XF','*.log','server.pid','server-info.json','public-url.txt'
  )
  & robocopy @args|Out-Null
  if($LASTEXITCODE -ge 8){throw 'Could not create the automatic Connectopoly backup.'}
  return $dest
}
function Apply-PendingHubPayload(){
  if(-not(Test-Path -LiteralPath $PendingHubPayload)){return $false}
  New-Item -ItemType Directory -Path $HubRoot -Force|Out-Null
  $hubBackupDir=Join-Path $BackupRoot 'Hub'
  New-Item -ItemType Directory -Path $hubBackupDir -Force|Out-Null
  if(Test-Path -LiteralPath $HubPath){$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';Copy-Item -LiteralPath $HubPath -Destination (Join-Path $hubBackupDir ('Trew Games Hub_'+$stamp+'.hta')) -Force}
  $text=[IO.File]::ReadAllText($PendingHubPayload)
  if($text -notmatch '<HTA:APPLICATION' -or $text -notmatch 'var\s+HUB_VERSION="[^"]+"'){throw 'The bundled Trew Games Hub update failed validation.'}
  $tempHub=$HubPath+'.incoming'
  Copy-Item -LiteralPath $PendingHubPayload -Destination $tempHub -Force
  Move-Item -LiteralPath $tempHub -Destination $HubPath -Force
  Remove-Item -LiteralPath $PendingHubPayload -Force -ErrorAction SilentlyContinue
  Log 'Applied bundled Trew Games Hub update.'
  return $true
}

function Restore-Game([string]$Backup){
  if(-not(Test-Path -LiteralPath $Backup)){return}
  $args=@($Backup,$GameRoot,'/E','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
  & robocopy @args|Out-Null
}
function Install-Manifest($manifest,[switch]$Force){
  if(-not(Test-Path -LiteralPath $GameRoot)){throw 'Connectopoly is not installed on this PC.'}

  $local=Get-LocalVersion
  $remote=[string]$manifest.version
  if(-not$Force -and (Normalize-Version $remote) -le (Normalize-Version $local)){return $false}

  if(Test-GameRunning){
    if($Mode -eq 'Check'){
      Write-Status 'pending' ("Update {0} is waiting for Connectopoly to close." -f $remote) $remote
      Log 'Game is running; update deferred.'
      return $false
    }

    Get-Process -Name Connectopoly -ErrorAction SilentlyContinue|ForEach-Object{
      try{
        if($_.Path -and [IO.Path]::GetFullPath($_.Path)-eq[IO.Path]::GetFullPath($GameExe)){
          Stop-Process -Id $_.Id -Force
        }
      }catch{}
    }
    Start-Sleep -Milliseconds 500
  }

  $work=Join-Path $env:TEMP ('TrewConnectopolyUpdate_'+[guid]::NewGuid().ToString('N'))
  $zip=Join-Path $work 'package.zip'
  $extract=Join-Path $work 'extract'
  New-Item -ItemType Directory -Path $work -Force|Out-Null
  $backup=$null

  try{
    Write-Status 'downloading' ("Downloading Connectopoly {0}..." -f $remote) $remote
    Invoke-WebRequest -Uri ([string]$manifest.packageUrl) -OutFile $zip -UseBasicParsing -TimeoutSec 300

    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
    if($hash -ne ([string]$manifest.sha256).ToUpperInvariant()){
      throw 'The downloaded update failed its SHA-256 integrity check.'
    }

    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $pkg=Join-Path $extract 'Connectopoly'
    if(-not(Test-Path -LiteralPath $pkg)){throw 'The downloaded update does not contain a Connectopoly package.'}

    $meta=Join-Path $pkg 'TREW_PACKAGE.json'
    if(-not(Test-Path -LiteralPath $meta)){throw 'The downloaded package is missing TREW_PACKAGE.json.'}
    $pkgMeta=Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json
    if([string]$pkgMeta.version -ne $remote){throw 'The downloaded package version does not match the update manifest.'}

    Write-Status 'backing-up' 'Creating recovery backup...' $remote
    $backup=Backup-Game $local

    Write-Status 'installing' ("Installing Connectopoly {0}..." -f $remote) $remote
    Get-ChildItem -LiteralPath $pkg -Force|ForEach-Object{
      Copy-Item -LiteralPath $_.FullName -Destination $GameRoot -Recurse -Force
    }

    Apply-PendingHubPayload|Out-Null

    if(-not(Test-Path -LiteralPath $GameExe)){throw 'Connectopoly.exe is missing after the update.'}
    if(-not(Test-Path -LiteralPath (Join-Path $GameRoot 'server.js'))){throw 'server.js is missing after the update.'}
    if(-not(Test-Path -LiteralPath (Join-Path $GameRoot 'public\player.html'))){throw 'player.html is missing after the update.'}

    [pscustomobject]@{
      game='Connectopoly';version=$remote;protocolVersion=[string]$manifest.protocolVersion;
      channel=[string]$manifest.channel;installedUtc=(Get-Date).ToUniversalTime().ToString('o')
    }|ConvertTo-Json|Set-Content -LiteralPath $VersionPath -Encoding UTF8

    @("Connectopoly $remote","",([string]$manifest.notes))|
      Set-Content -LiteralPath (Join-Path $UpdaterRoot 'last-update.txt') -Encoding UTF8

    Write-Status 'ready' ("Connectopoly {0} is installed." -f $remote) $remote
    Log ("Updated Connectopoly from $local to $remote. Backup: $backup")
    return $true
  }catch{
    Log ('Update failed: '+$_.Exception.Message)
    if($backup){
      try{Restore-Game $backup;Log 'Rollback completed.'}catch{Log ('Rollback failed: '+$_.Exception.Message)}
    }
    Write-Status 'error' $_.Exception.Message $remote
    throw
  }finally{
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
function Check-SelfUpdate($cfg){
  try{
    $base=([string]$cfg.repoRawBase).TrimEnd('/')
    if(-not$base){return}
    $uri=$base+'/client/version.json?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $info=Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 12
    if((Normalize-Version ([string]$info.version)) -le (Normalize-Version $ClientVersion)){return}

    $new=Join-Path $UpdaterRoot 'TrewUpdateClient.ps1.new'
    Invoke-WebRequest -Uri ([string]$info.scriptUrl) -OutFile $new -UseBasicParsing -TimeoutSec 30
    $hash=(Get-FileHash -LiteralPath $new -Algorithm SHA256).Hash.ToUpperInvariant()
    if($hash -ne ([string]$info.sha256).ToUpperInvariant()){
      Remove-Item $new -Force -ErrorAction SilentlyContinue
      return
    }
    Move-Item -LiteralPath $new -Destination $PSCommandPath -Force
    Log ("Updater self-updated to "+[string]$info.version)
  }catch{
    Log ('Self-update check skipped: '+$_.Exception.Message)
  }
}

try{
  $cfg=Get-Config
  Check-SelfUpdate $cfg
  Apply-PendingHubPayload|Out-Null

  $manifest=Get-Manifest $cfg
  $local=Get-LocalVersion
  $remote=[string]$manifest.version
  $needs=(Normalize-Version $remote) -gt (Normalize-Version $local)

  if($Mode -eq 'Status'){
    $msg="Channel: $($cfg.channel)`r`nInstalled: $local`r`nLatest: $remote`r`n`r`n$([string]$manifest.notes)"
    Notify $msg 'Trew Games Update Status'
    Write-Output $msg
    exit 0
  }

  if($Mode -eq 'Repair'){
    Install-Manifest $manifest -Force|Out-Null
    Notify ("Connectopoly $remote was verified/reinstalled successfully.") 'Trew Games Repair'
    exit 0
  }

  if($Mode -eq 'Update'){
    if($needs){
      Install-Manifest $manifest|Out-Null
      Notify ("Connectopoly updated to $remote.")
    }else{
      Notify ("Connectopoly is already current at $local.")
    }
    exit 0
  }

  if($needs -and [bool]$cfg.autoUpdate){
    Install-Manifest $manifest|Out-Null
  }

  if($Mode -eq 'Launch'){
    if(-not(Test-Path -LiteralPath $GameExe)){throw 'Connectopoly.exe could not be found.'}
    Start-Process -FilePath $GameExe -WorkingDirectory $GameRoot
  }

  exit 0
}catch{
  Log ('Fatal updater error: '+$_.Exception.Message)
  Write-Status 'error' $_.Exception.Message

  if($Mode -eq 'Launch' -and (Test-Path -LiteralPath $GameExe)){
    Notify ("The update check failed, so Connectopoly will open using the current installed version.`r`n`r`n"+$_.Exception.Message) 'Trew Games Updater'
    Start-Process -FilePath $GameExe -WorkingDirectory $GameRoot
    exit 0
  }

  if(-not$Quiet){Notify $_.Exception.Message 'Trew Games Updater'}
  exit 1
}
