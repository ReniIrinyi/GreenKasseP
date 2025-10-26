# ===========================
# GreenKasse – Installer
# ===========================

$ErrorActionPreference = "Stop"

$AppVersion = "1.0.0"
$PwaVersion = "1.0.0"

$Port       = 8080                           # .NET app port
$AppExeName = "GreenKasse.Web.exe"          # app  exe
$UpdaterExe = "GreenKasse.Updater.exe"      # updater exe 
$UpdaterArgs = "--service"                  

$PF = "C:\Program Files\GreenKasse"
$PD = "C:\ProgramData\GreenKasse"

# ---- (BundleRoot) ----
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path  # ..\BundleRoot\scripts
$ROOT = Split-Path $ROOT                                  # ..\BundleRoot   

$AppZip     = Join-Path $ROOT ("App_{0}.zip" -f $AppVersion)
$PwaZip     = Join-Path $ROOT ("Pwa_{0}.zip" -f $PwaVersion)

$AppSrc     = Join-Path $ROOT "app"
$PwaSrc     = Join-Path $ROOT "app\pwa"
$UpdaterSrc = Join-Path $ROOT "app\updater"

$DbSrc     = Join-Path $ROOT "db"
$SchemaDir = Join-Path $ROOT "db\schemas"

# ---- Servicenames ----
$SvcApp = "GreenKasse App"
$SvcUpd = "GreenKasse Updater"
$SvcDb  = "GreenKasseDB"

# ---- Admin check ----
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  Write-Error "Bitte führe als Admin aus"
  exit 1
}

# ---- Helpers ----
function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

function New-Junction($link, $target) {
  if (Test-Path $link) {
    cmd /c rmdir "$link" | Out-Null 2>$null
  }
  cmd /c mklink /J "$link" "$target" | Out-Null
}

function StopAndDelete-Service($name) {
  $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
  if ($svc) {
    try { Stop-Service $name -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep 1
    sc.exe delete "$name" | Out-Null
    Start-Sleep 1
  }
}

function Add-UrlAcl($url, $user) {
  $exists = (cmd /c netsh http show urlacl url=$url) 2>$null
  if ($LASTEXITCODE -eq 0 -and "$exists".Contains($url)) { return }
  cmd /c netsh http add urlacl url=$url user="$user" | Out-Null
}

function Add-Firewall($name, $port) {
  try {
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
    }
  } catch { Write-Warning "Ich konnte keinen Firewall-Regel erstellen: $($_.Exception.Message)" }
}

function Get-StrongPassword([int]$len = 24) {
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] ($len)
  $rng.GetBytes($bytes)
  [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/','A').Replace('+','B')
}

function Exec-Quiet($file, $args) {
  Write-Host " > $file $args"
  $p = Start-Process -FilePath $file -ArgumentList $args -PassThru -WindowStyle Hidden -Wait
  if ($p.ExitCode -ne 0) { throw "Error: $file $args (ExitCode=$($p.ExitCode))" }
}

Write-Host "== Installiere GreenKasse =="
Ensure-Dir $PF
Ensure-Dir $PD
Ensure-Dir (Join-Path $PF "App")
Ensure-Dir (Join-Path $PF "Updater")
Ensure-Dir (Join-Path $PF "db")
Ensure-Dir (Join-Path $PD "packages\app\$AppVersion")
Ensure-Dir (Join-Path $PD "packages\pwa\$PwaVersion")
Ensure-Dir (Join-Path $PD "content\pwa")
Ensure-Dir (Join-Path $PD "session")
Ensure-Dir (Join-Path $PD "cache")
Ensure-Dir (Join-Path $PD "logs")
Ensure-Dir (Join-Path $PD "backup")

if (-not (Test-Path (Join-Path $DbSrc "mariadb\bin"))) { throw "MariaDB bin sollte unter BundleRoot\db liegen." }

# ---- Updater  ----
if (Test-Path $UpdaterSrc) {
  Write-Host "kopiere Updater -> $($PF)\Updater"
  Copy-Item "$UpdaterSrc\*" "$PF\Updater\" -Recurse -Force
}


# App 
Add-Type -AssemblyName System.IO.Compression.FileSystem
$AppTarget = Join-Path $PD "packages\app\$AppVersion"
if (Test-Path $AppZip) {
  Write-Host "App aus ZIP -> $AppTarget"
  [System.IO.Compression.ZipFile]::ExtractToDirectory($AppZip, $AppTarget)
} else {
  Write-Host "App aus Ordner -> $AppTarget"
  Copy-Item "$AppSrc\*" $AppTarget -Recurse -Force
}

# PWA 
$PwaTarget = Join-Path $PD "packages\pwa\$PwaVersion"
if (Test-Path $PwaZip) {
  Write-Host "PWA aus ZIP -> $PwaTarget"
  [System.IO.Compression.ZipFile]::ExtractToDirectory($PwaZip, $PwaTarget)
} else {
  Write-Host "PWA aus Ordner -> $PwaTarget"
  Copy-Item "$PwaSrc\*" $PwaTarget -Recurse -Force
}

# ---- „current” junctions ----
New-Junction "$PF\App\current" "$PD\packages\app\$AppVersion"
New-Junction "$PD\content\pwa\current" "$PD\packages\pwa\$PwaVersion"

# ---- MariaDB ----
if (-not (Test-Path (Join-Path $DbSrc "mariadb\bin"))) { throw "MariaDB bin sollte unter BundleRoot\db\mariadb\bin liegen." }

Write-Host "MariaDB bundle kopieren -> $PF\db"
Copy-Item "$DbSrc\*" "$PF\db\" -Recurse -Force

$DbBin    = Join-Path $PF "db\mariadb\bin"
$MyIni    = Join-Path $PF "db\my.ini"
$DataDir  = Join-Path $PD "db\data"              
$ExportDir= Join-Path $DataDir "export"
Ensure-Dir $DataDir
Ensure-Dir $ExportDir

cmd /c icacls "$DataDir" /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)M" /T | Out-Null

$ini = Get-Content $MyIni -Raw
$ini = $ini -replace '\{app\}\\db\\mariadb',[Regex]::Escape("$PF\db\mariadb").Replace('\\','\\\\')
$ini = $ini -replace '\{app\}\\db\\data',[Regex]::Escape($DataDir).Replace('\\','\\\\')
$ini = $ini -replace 'secure-file-priv\s*=\s*.*',"secure-file-priv=$ExportDir"
$ini | Set-Content $MyIni -Encoding ASCII

# mariadbd.exe or mysqld.exe
$SrvExe = if (Test-Path (Join-Path $DbBin "mariadbd.exe")) { Join-Path $DbBin "mariadbd.exe" } else { Join-Path $DbBin "mysqld.exe" }
$Mysql  = Join-Path $DbBin "mysql.exe"

# ---- MariaDB init wenn keine data vorhanden ----
if ((Get-ChildItem $DataDir -Force | Measure-Object).Count -eq 0) {
  Write-Host "Init MariaDB…"
  Exec-Quiet $SrvExe "--defaults-file=""$MyIni"" --initialize-insecure"
}

# ---- DB Service ----
StopAndDelete-Service $SvcDb
$binPath = """$SrvExe"" --defaults-file=""$MyIni"""
Exec-Quiet "sc.exe" "create ""$SvcDb"" binPath= $binPath start= auto obj= ""NT AUTHORITY\LocalService"""
Exec-Quiet "sc.exe" "description ""$SvcDb"" ""GreenKasse MariaDB (local)"""
Exec-Quiet "sc.exe" "start ""$SvcDb"""
Start-Sleep 4

# ---- Passwort + Db init ----
$DbPwd = Get-StrongPassword 24
Write-Host "Initialisiere lokale Datenbank…"
# root pw
Exec-Quiet $Mysql "-u root -e ""ALTER USER 'root'@'localhost' IDENTIFIED BY '$DbPwd'; FLUSH PRIVILEGES;"""
# DB + user
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""CREATE DATABASE IF NOT EXISTS greenKasse CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"""
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""CREATE USER IF NOT EXISTS 'lsa'@'localhost' IDENTIFIED BY '$DbPwd';"""
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""GRANT ALL PRIVILEGES ON greenKasse.* TO 'lsa'@'localhost'; FLUSH PRIVILEGES;"""

# Schema/seed import
if (Test-Path $Schema) {
  Exec-Quiet "cmd.exe" "/c `"$Mysql`" -u lsa -p$DbPwd greenKasse < `"$Schema`""
}
if (Test-Path $Seed) {
  Exec-Quiet "cmd.exe" "/c `"$Mysql`" -u lsa -p$DbPwd greenKasse < `"$Seed`""
}

# ---- appsettings.json anpassen ----
$AppSettings = Join-Path $PF "App\current\appsettings.json"
if (-not (Test-Path $AppSettings)) { throw "appsettings.json nem található: $AppSettings" }

$json = Get-Content $AppSettings -Raw | ConvertFrom-Json -Depth 100

function Ensure-Section([object]$root, [string]$name) {
  if (-not ($root.PSObject.Properties.Name -contains $name)) {
    $root | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{})
  }
}

$json.WebRoot = "C:\\ProgramData\\GreenKasse\\content\\pwa\\current"

Ensure-Section $json 'Paths'
$pathsWanted = @{
  BasePath = "C:\\ProgramData\\GreenKasse\\"
  Session  = "C:\\ProgramData\\GreenKasse\\session"
  Cache    = "C:\\ProgramData\\GreenKasse\\cache"
  Packages = "C:\\ProgramData\\GreenKasse\\packages"
  Content  = "C:\\ProgramData\\GreenKasse\\content"
}
foreach ($k in $pathsWanted.Keys) {
  if ($json.Paths.PSObject.Properties.Name -contains $k) {
    $json.Paths.$k = $pathsWanted[$k]
  } else {
    $json.Paths | Add-Member -NotePropertyName $k -NotePropertyValue $pathsWanted[$k]
  }
}

Ensure-Section $json 'ConnectionStrings'
$json.ConnectionStrings.MariaDb = "Server=localhost;Port=3306;Database=greenKasse;User=lsa;Password=$DbPwd;TreatTinyAsBoolean=true;"

$json | ConvertTo-Json -Depth 100 | Set-Content $AppSettings -Encoding UTF8

# ---- URL ACL ----
$Url = "http://+:$Port/"
Add-UrlAcl -url $Url -user "NT AUTHORITY\LOCAL SERVICE"
Add-Firewall -name "GreenKasse $Port" -port $Port

# ---- Services (App + Updater) ----
StopAndDelete-Service $SvcApp
StopAndDelete-Service $SvcUpd

# App service
$AppExe = """$PF\App\current\$AppExeName"""
Exec-Quiet "sc.exe" "create ""$SvcApp"" binPath= $AppExe start= auto obj= ""NT AUTHORITY\LocalService"""
Exec-Quiet "sc.exe" "description ""$SvcApp"" ""GreenKasse .NET app"""
Exec-Quiet "sc.exe" "failure ""$SvcApp"" reset= 86400 actions= restart/5000"

# Updater service 
if ((Test-Path (Join-Path $PF "Updater\$UpdaterExe")) -and ($UpdaterExe -ne "")) {
  $UpdPath = """$PF\Updater\$UpdaterExe"""
  $UpdBin  = if ([string]::IsNullOrWhiteSpace($UpdaterArgs)) { $UpdPath } else { "$UpdPath $UpdaterArgs" }
  Exec-Quiet "sc.exe" "create ""$SvcUpd"" binPath= $UpdBin start= delayed-auto obj= ""NT AUTHORITY\LocalService"""
  Exec-Quiet "sc.exe" "description ""$SvcUpd"" ""GreenKasse updater"""
  Exec-Quiet "sc.exe" "failure ""$SvcUpd"" reset= 86400 actions= restart/5000"
}

# ---- Run ----
try { Start-Service "$SvcDb"  -ErrorAction SilentlyContinue } catch {}
try { Start-Service "$SvcUpd" -ErrorAction SilentlyContinue } catch {}
try { Start-Service "$SvcApp" -ErrorAction SilentlyContinue } catch {}

Write-Host "== Greenkasse ist installiert =="
Write-Host ("URL: http://localhost:{0}/" -f $Port)
Write-Host ("PWA: {0}" -f (Join-Path $PD "content\pwa\current"))
Write-Host ("App: {0}" -f (Join-Path $PF "App\current"))

# ---- PWA Auto-Start ----
$OpenUrl = "http://localhost:$Port/"

$ok = $false
for ($i=0; $i -lt 20; $i++) {
  try { Invoke-WebRequest -Uri $OpenUrl -UseBasicParsing -TimeoutSec 2 | Out-Null; $ok = $true; break } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ok) { Write-Warning "Backend noch nicht erreichbar, versuche trotzdem Browser-Start..." }

$edge   = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$edge64 = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
$chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
$chrome64 = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"

function Start-AppWindow($exe, $url) {
  if (Test-Path $exe) {
    Start-Process -FilePath $exe -ArgumentList "--app=`"$url`"" | Out-Null
    return $true
  }
  return $false
}

if (-not (Start-AppWindow $edge $OpenUrl) -and
    -not (Start-AppWindow $edge64 $OpenUrl) -and
    -not (Start-AppWindow $chrome $OpenUrl) -and
    -not (Start-AppWindow $chrome64 $OpenUrl)) {
  Start-Process $OpenUrl | Out-Null
}

