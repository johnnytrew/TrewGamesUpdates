$ErrorActionPreference='Stop'

$updaterRoot=Join-Path $env:LOCALAPPDATA 'TrewGamesUpdater'
$clientPath=Join-Path $updaterRoot 'TrewUpdateClient.ps1'
$hiddenRunner=Join-Path $updaterRoot 'TrewUpdateCheckHidden.vbs'
$taskName='Trew Games Automatic Update Check'

if(-not(Test-Path -LiteralPath $clientPath)){
  throw 'Trew Games Updater is not installed for this Windows account.'
}

$runnerText=@'
Option Explicit

Dim shell, files, updaterRoot, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")

updaterRoot = files.GetParentFolderName(WScript.ScriptFullName)
scriptPath = files.BuildPath(updaterRoot, "TrewUpdateClient.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ _
    & scriptPath & """ -Mode Check -Quiet"

shell.Run command, 0, True
'@
$enc=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($hiddenRunner,$runnerText,$enc)

$scheduler=New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$folder=$scheduler.GetFolder('\')
$task=$folder.GetTask('\'+$taskName)
$definition=$task.Definition
$definition.Actions.Clear()
$action=$definition.Actions.Create(0)
$action.Path=Join-Path $env:WINDIR 'System32\wscript.exe'
$action.Arguments='"'+$hiddenRunner+'"'
$folder.RegisterTaskDefinition($taskName,$definition,6,$null,$null,3,$null)|Out-Null

Write-Host 'Trew Games background update window fix installed successfully.' -ForegroundColor Green
Write-Host 'Games, saves, and Hub settings were not changed.'
