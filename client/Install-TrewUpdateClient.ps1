param(
  [Parameter(Mandatory=$true)][string]$ManifestBaseUrl,
  [Parameter(Mandatory=$true)][string]$RepoRawBase,
  [ValidateSet('stable','beta','developer')][string]$DefaultChannel='stable'
)
$ErrorActionPreference='Stop'

$src=$PSScriptRoot
$root=Join-Path $env:LOCALAPPDATA 'TrewGamesUpdater'
$game=Join-Path $env:LOCALAPPDATA 'Bripardy\games\Connectopoly'
$hub=Join-Path $env:LOCALAPPDATA 'Bripardy\Trew Games Hub.hta'

New-Item -ItemType Directory -Path $root -Force|Out-Null

foreach($f in @(
  'TrewUpdateClient.ps1',
  'Set-TrewChannel.ps1',
  'Trew Update Center.hta',
  'ConnectopolyAutoLauncher.cs'
)){
  $p=Join-Path $src $f
  if(-not(Test-Path -LiteralPath $p)){throw ('Client installer payload is missing '+$f)}
  Copy-Item -LiteralPath $p -Destination (Join-Path $root $f) -Force
}

[pscustomobject]@{
  manifestBaseUrl=$ManifestBaseUrl.TrimEnd('/');
  repoRawBase=$RepoRawBase.TrimEnd('/');
  channel=$DefaultChannel;
  autoUpdate=$true;
  checkOnLaunch=$true
}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'config.json') -Encoding UTF8

$compiler=@(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)|Where-Object{Test-Path -LiteralPath $_}|Select-Object -First 1

if(-not$compiler){throw 'Windows C# compiler was not found.'}

$out=Join-Path $root 'Connectopoly Auto Launcher.exe'
$cs=Join-Path $root 'ConnectopolyAutoLauncher.cs'
$args=@(
  '/nologo','/target:winexe',
  ('/out:"'+$out+'"'),
  '/reference:System.dll',
  '/reference:System.Windows.Forms.dll',
  ('"'+$cs+'"')
)
& $compiler @args
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $out)){
  throw 'Could not build the Connectopoly auto-launcher.'
}

if(Test-Path -LiteralPath $hub){
  $backup=$hub+'.before-auto-updater'
  if(-not(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $hub -Destination $backup -Force}

  $txt=[IO.File]::ReadAllText($hub)
  if($txt -notmatch 'TREW_AUTO_UPDATE_LAUNCHER'){
    $pattern='function futureExe\(id\)\{[^\r\n]*\}'
    $replacement='function futureExe(id){/* TREW_AUTO_UPDATE_LAUNCHER */if(id==="mono"){var u=fso.BuildPath(shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\TrewGamesUpdater"),"Connectopoly Auto Launcher.exe");if(fso.FileExists(u))return u;}var folder=id==="feud"?"TrewFeud":"Connectopoly";return fso.BuildPath(fso.BuildPath(fso.BuildPath(getRoot(),"games"),folder),folder+".exe");}'
    $new=[regex]::Replace($txt,$pattern,$replacement,1)
    if($new -ne $txt){
      $enc=New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($hub,$new,$enc)
    }
  }
}

$ws=New-Object -ComObject WScript.Shell
$desktop=[Environment]::GetFolderPath('Desktop')
$ico=Join-Path $game 'Connectopoly.ico'

$sc=$ws.CreateShortcut((Join-Path $desktop 'Connectopoly.lnk'))
$sc.TargetPath=$out
$sc.WorkingDirectory=$game
if(Test-Path -LiteralPath $ico){$sc.IconLocation=$ico+',0'}
$sc.Description='Connectopoly - checks for Trew Games updates before launch'
$sc.Save()

$uc=$ws.CreateShortcut((Join-Path $desktop 'Trew Update Center.lnk'))
$uc.TargetPath=(Join-Path $env:WINDIR 'System32\mshta.exe')
$uc.Arguments='"'+(Join-Path $root 'Trew Update Center.hta')+'"'
$uc.WorkingDirectory=$root
if(Test-Path -LiteralPath $ico){$uc.IconLocation=$ico+',0'}
$uc.Save()

try{
  $taskName='Trew Games Automatic Update Check'
  $script=Join-Path $root 'TrewUpdateClient.ps1'
  $tr='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$script+'" -Mode Check -Quiet'
  & schtasks.exe /Create /F /SC HOURLY /MO 6 /TN $taskName /TR $tr|Out-Null
}catch{}

Write-Host 'Trew Games automatic updater installed.' -ForegroundColor Green
