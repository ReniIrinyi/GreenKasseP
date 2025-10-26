# ===========================
# GreenKasse – Installer
# ===========================

$ErrorActionPreference = "Stop"

# ---- Versionen / App-Dateien ----
$AppVersion = "1.0.0"
$PwaVersion = "1.0.0"

$Port       = 8080                           # .NET App Port
$AppExeName = "GreenKasse.Web.exe"           # Haupt-App EXE
$UpdaterExe = "GreenKasse.Updater.exe"       # Updater EXE (optional)
$UpdaterArgs = "--service"

# ---- Zielpfade ----
$PF = "C:\Program Files\GreenKasse"
$PD = "C:\ProgramData\GreenKasse"

# ---- BundleRoot (dieses Skript liegt unter BundleRoot\scripts) ----
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path $ROOT  # BundleRoot

# Quellen im Bundle
$AppZip     = Join-Path $ROOT ("App_{0}.zip" -f $AppVersion)
$PwaZip     = Join-Path $ROOT ("Pwa_{0}.zip" -f $PwaVersion)         # bevorzugt
if (-not (Test-Path $PwaZip)) { $PwaZip = Join-Path $ROOT ("Pwa_{0}.zip" -f $AppVersion) } # Fallback
$AppSrc     = Join-Path $ROOT "app"
$PwaSrc     = Join-Path $ROOT "app\pwa"
$UpdaterSrc = Join-Path $ROOT "app\updater"

$DbSrc      = Join-Path $ROOT "db"
$SchemaDir  = Join-Path $ROOT "db\schemas"
$Schema     = Join-Path $SchemaDir "schema.sql"
$Seed       = Join-Path $SchemaDir "seed.sql"

# ---- Service-Namen ----
$SvcApp = "GreenKasse App"
$SvcUpd = "GreenKasse Updater"
$SvcDb  = "GreenKasseDB"

# ---- Admin-Pruefung ----
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  Write-Error "Bitte als Administrator ausfuehren."
  exit 1
}

# ---- Helfer ----
function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}
function New-Junction($link, $target) {
  if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null 2>$null }
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
  } catch { Write-Warning "Firewall-Regel konnte nicht erstellt werden: $($_.Exception.Message)" }
}
function Get-StrongPassword([int]$len = 24) {
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] ($len)
  $rng.GetBytes($bytes)
  [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/','A').Replace('+','B')
}
function Exec-Quiet($file, [string]$args = $null) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file
  if ($args) { $psi.Arguments = $args }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) {
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    throw "Fehler: $file $args (ExitCode=$($p.ExitCode))`nSTDOUT:`n$out`nSTDERR:`n$err"
  }
}



Write-Host "== Installiere GreenKasse =="

# ---- Zielstruktur ----
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
Ensure-Dir (Join-Path $PD "db\data")

if (-not (Test-Path (Join-Path $DbSrc "mariadb\bin"))) { throw "MariaDB bin fehlt unter BundleRoot\db\mariadb\bin." }

# ---- Updater  ----
if (Test-Path $UpdaterSrc) {
  Write-Host "Kopiere Updater -> $($PF)\Updater"
  Copy-Item "$UpdaterSrc\*" "$PF\Updater\" -Recurse -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Expand-ZipFlatten($zipPath, $targetDir, $topFolderName) {
  if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
  New-Item -ItemType Directory -Path $targetDir | Out-Null

  $tmp = Join-Path $env:TEMP ("GK_unzip_" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tmp)

  $top = Join-Path $tmp $topFolderName
if ((Test-Path $top) -and ((Get-ChildItem $tmp | Measure-Object).Count -eq 1)) {
    Copy-Item "$top\*" $targetDir -Recurse -Force
  } else {
    Copy-Item "$tmp\*" $targetDir -Recurse -Force
  }
  Remove-Item $tmp -Recurse -Force
}

# ---- App ----
$AppTarget = Join-Path $PD "packages\app\$AppVersion"
if (Test-Path $AppZip) {
  Write-Host "App aus ZIP -> $AppTarget"
  Expand-ZipFlatten -zipPath $AppZip -targetDir $AppTarget -topFolderName "app"
} else {
  Write-Host "App aus Ordner -> $AppTarget"
  if (Test-Path $AppTarget) { Remove-Item $AppTarget -Recurse -Force }
  Copy-Item "$AppSrc\*" $AppTarget -Recurse -Force
}

# ---- PWA aus ZIP ODER Ordner ----
$PwaTarget = Join-Path $PD "packages\pwa\$PwaVersion"

if (Test-Path $PwaTarget) { Remove-Item $PwaTarget -Recurse -Force }
New-Item -ItemType Directory -Path $PwaTarget | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $PwaZip) {
  Write-Host "PWA aus ZIP -> $PwaTarget"
  $tmp = Join-Path $env:TEMP ("gk_pwa_" + [guid]::NewGuid())
  [System.IO.Compression.ZipFile]::ExtractToDirectory($PwaZip, $tmp)

  $entries = Get-ChildItem $tmp
  $top = if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $entries[0].FullName } else { $tmp }

  Copy-Item "$top\*" $PwaTarget -Recurse -Force
  Remove-Item $tmp -Recurse -Force
}
else {
  Write-Host "PWA aus Ordner -> $PwaTarget"
  if (-not (Test-Path $PwaSrc)) { throw "PWA-Quellordner nicht gefunden: $PwaSrc" }
  Copy-Item "$PwaSrc\*" $PwaTarget -Recurse -Force
}

# ---- „current” Junctions ----
New-Junction "$PF\App\current" "$PD\packages\app\$AppVersion"
New-Junction "$PD\content\pwa\current" "$PD\packages\pwa\$PwaVersion"

# ---- MariaDB in Program Files, Daten nach ProgramData ----
Write-Host "MariaDB-Bundle kopieren -> $PF\db"
Copy-Item "$DbSrc\*" "$PF\db\" -Recurse -Force

$DbBin    = Join-Path $PF "db\mariadb\bin"
$MyIni    = Join-Path $PF "db\my.ini"
$DataDir  = Join-Path $PD "db\data"
$ExportDir= Join-Path $DataDir "export"
Ensure-Dir $ExportDir

# Rechte fuer LocalService auf Data-Ordner
cmd /c "icacls ""$DataDir"" /grant *S-1-5-19:(OI)(CI)M /T" | Out-Null

# Platzhalter in my.ini ersetzen
$ini = Get-Content $MyIni -Raw
$ini = $ini -replace '\{app\}\\db\\mariadb',[Regex]::Escape("$PF\db\mariadb").Replace('\\','\\\\')
$ini = $ini -replace '\{app\}\\db\\data',[Regex]::Escape($DataDir).Replace('\\','\\\\')
$ini = $ini -replace 'secure-file-priv\s*=\s*.*',"secure-file-priv=$ExportDir"
$ini | Set-Content $MyIni -Encoding ASCII

# mariadbd.exe oder mysqld.exe bestimmen
$SrvExe = if (Test-Path (Join-Path $DbBin "mariadbd.exe")) { Join-Path $DbBin "mariadbd.exe" } else { Join-Path $DbBin "mysqld.exe" }
$Mysql  = Join-Path $DbBin "mysql.exe"

# ---- MariaDB initialisieren (nur wenn data leer) ----
if ((Get-ChildItem $DataDir -Force | Measure-Object).Count -eq 0) {
  Write-Host "Init MariaDB…"
  Exec-Quiet $SrvExe "--defaults-file=""$MyIni"" --initialize-insecure --datadir=""$DataDir"""
}

# ---- DB-Service anlegen und starten ----
StopAndDelete-Service $SvcDb
$binPath = """$SrvExe"" --defaults-file=""$MyIni"""
Exec-Quiet "sc.exe" "create ""$SvcDb"" binPath= $binPath start= auto obj= ""NT AUTHORITY\LocalService"""
Exec-Quiet "sc.exe" "description ""$SvcDb"" ""GreenKasse MariaDB (local)"""
Exec-Quiet "sc.exe" "start ""$SvcDb"""
Start-Sleep 4

# ---- Passwort setzen, DB+User anlegen, Schema importieren ----
$DbPwd = Get-StrongPassword 24
Write-Host "Initialisiere lokale Datenbank (Benutzer & Schema)…"

# root Passwort
Exec-Quiet $Mysql "-u root -e ""ALTER USER 'root'@'localhost' IDENTIFIED BY '$DbPwd'; FLUSH PRIVILEGES;"""

# DB + User
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""CREATE DATABASE IF NOT EXISTS greenKasse CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"""
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""CREATE USER IF NOT EXISTS 'lsa'@'localhost' IDENTIFIED BY '$DbPwd';"""
Exec-Quiet $Mysql "-u root -p$DbPwd -e ""GRANT ALL PRIVILEGES ON greenKasse.* TO 'lsa'@'localhost'; FLUSH PRIVILEGES;"""

# Schema/Seed (per cmd Umleitung, damit '< file.sql' funktioniert)
if (Test-Path $Schema) { Exec-Quiet "cmd.exe" "/c `"$Mysql`" -u lsa -p$DbPwd greenKasse < `"$Schema`"" }
if (Test-Path $Seed)   { Exec-Quiet "cmd.exe" "/c `"$Mysql`" -u lsa -p$DbPwd greenKasse < `"$Seed`""   }

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

# ---- HTTP-URL & Firewall ----
$Url = "http://+:$Port/"
Add-UrlAcl -url $Url -user "NT AUTHORITY\LOCAL SERVICE"
Add-Firewall -name "GreenKasse $Port" -port $Port

# ---- Dienste (App + Updater) ----
StopAndDelete-Service $SvcApp
StopAndDelete-Service $SvcUpd



# App Service
$AppExe = """$PF\App\current\$AppExeName"""
Exec-Quiet "sc.exe" "create ""$SvcApp"" binPath= $AppExe start= auto obj= ""NT AUTHORITY\LocalService"""
Exec-Quiet "sc.exe" "description ""$SvcApp"" ""GreenKasse .NET App"""
Exec-Quiet "sc.exe" "failure ""$SvcApp"" reset= 86400 actions= restart/5000"

# Updater Service (optional)
if ((Test-Path (Join-Path $PF "Updater\$UpdaterExe")) -and ($UpdaterExe -ne "")) {
  $UpdPath = """$PF\Updater\$UpdaterExe"""
  $UpdBin  = if ([string]::IsNullOrWhiteSpace($UpdaterArgs)) { $UpdPath } else { "$UpdPath $UpdaterArgs" }
  Exec-Quiet "sc.exe" "create ""$SvcUpd"" binPath= $UpdBin start= delayed-auto obj= ""NT AUTHORITY\LocalService"""
  Exec-Quiet "sc.exe" "description ""$SvcUpd"" ""GreenKasse Updater"""
  Exec-Quiet "sc.exe" "failure ""$SvcUpd"" reset= 86400 actions= restart/5000"
}

# ---- Start ----
try { Start-Service "$SvcDb"  -ErrorAction SilentlyContinue } catch {}
try { Start-Service "$SvcUpd" -ErrorAction SilentlyContinue } catch {}
try { Start-Service "$SvcApp" -ErrorAction SilentlyContinue } catch {}

Write-Host "== GreenKasse ist installiert =="
Write-Host ("URL: http://localhost:{0}/" -f $Port)
Write-Host ("PWA: {0}" -f (Join-Path $PD "content\pwa\current"))
Write-Host ("App: {0}" -f (Join-Path $PF "App\current"))

# ---- PWA Auto-Start im App-Fenster (Edge/Chrome), ansonsten Standardbrowser ----
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
  if (Test-Path $exe) { Start-Process -FilePath $exe -ArgumentList "--app=`"$url`"" | Out-Null; return $true }
  return $false
}
if (-not (Start-AppWindow $edge $OpenUrl) -and
    -not (Start-AppWindow $edge64 $OpenUrl) -and
    -not (Start-AppWindow $chrome $OpenUrl) -and
    -not (Start-AppWindow $chrome64 $OpenUrl)) {
  Start-Process $OpenUrl | Out-Null
}
