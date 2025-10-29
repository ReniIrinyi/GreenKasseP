# ===========================
# GreenKasse – Installer
# ===========================

[CmdletBinding()]
param(
  [ValidateSet("Auto","Local","External")]
  [string]$DbMode = "Auto",

# DB params (External)
  [string]$DbHost = "localhost",
  [int]$DbPort = 3307,
  [string]$DbName = "greenKasse1",
  [string]$DbUser = "lsa",
  [string]$DbPassword = "",

# Local DB
  [switch]$DbPreserveUsers
)

$ErrorActionPreference = "Stop"

# --- DB status flags (soft-fail) ---
$DbAttempted = $false
$DbOk        = $false
$DbError     = $null

# ---- App/PWA ----
$AppVersion = "1.0.0"
$PwaVersion = "1.0.0"

$Port       = 8080
$AppExeName = "GreenKasse.App.exe"
$UpdaterExe = "GreenKasse.Updater.exe"
$UpdaterArgs = "--service"

$PFroot = [Environment]::GetFolderPath('ProgramFiles')               # C:\Program Files
$PF     = Join-Path $PFroot 'GreenKasse'
$PD     = Join-Path $env:ProgramData 'GreenKasse'

# ---- BundleRoot ----
$ROOT       = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path
$AppZip     = Join-Path $ROOT ("App_{0}.zip" -f $AppVersion)
$PwaZip     = Join-Path $ROOT ("Pwa_{0}.zip" -f $PwaVersion)
if (-not (Test-Path $PwaZip)) { $PwaZip = Join-Path $ROOT ("Pwa_{0}.zip" -f $AppVersion) }

$AppSrc     = $ROOT
$PwaSrc     = Join-Path $ROOT "wwwroot"
$UpdaterSrc = Join-Path $ROOT "updater"

$DbSrc      = Join-Path $ROOT "db"
$SchemaDir  = Join-Path $ROOT "db\schemas"
$Schema     = Join-Path $SchemaDir "schema.sql"
$Seed       = Join-Path $SchemaDir "seed.sql"

$SvcApp = "GreenKasse App"
$SvcUpd = "GreenKasse Updater"
$SvcDb  = "GreenKasseDB"

# ---- Admin ----
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  Write-Error "Bitte als Administrator ausfuehren."
  exit 1
}

# ====================== Helpers ======================

function Start-AppWindow {
  param([string]$exe,[string]$url)
  if (Test-Path $exe) {
    Start-Process -FilePath $exe -ArgumentList "--app=$url" | Out-Null
    return $true
  }
  return $false
}

function Set-ContentUtf8NoBom {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $Value
  )
  $enc = New-Object System.Text.UTF8Encoding($false)  # $false => ohne BOM
  [System.IO.File]::WriteAllText($Path, $Value, $enc)
}

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
  try { cmd /c netsh http add urlacl url=$url user="$user" | Out-Null } catch {}
}
function Add-Firewall($name, $port) {
  try {
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
    }
  } catch { Write-Warning "Firewall warning: $($_.Exception.Message)" }
}
function Get-StrongPassword([int]$len = 24) {
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] ($len)
  $rng.GetBytes($bytes)
  [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/','A').Replace('+','B')
}
function Invoke-Sc {
  param(
    [Parameter(Mandatory)] [string] $Args,
    [int[]] $IgnoreExitCodes = @()
  )
  if ([string]::IsNullOrWhiteSpace($Args)) { throw "Invoke-Sc: arguments are empty." }
  Write-Host " > sc.exe $Args"
  $p = Start-Process -FilePath "sc.exe" -ArgumentList $Args -PassThru -WindowStyle Hidden -Wait
  if ($IgnoreExitCodes -contains $p.ExitCode) { Write-Host "   (ignored exit code $($p.ExitCode))"; return }
  if ($p.ExitCode -ne 0) { Write-Warning "Fehler: sc.exe $Args (ExitCode=$($p.ExitCode))" }
}
function Extract-Zip-Clean($zipPath, $dest) {
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Ensure-Dir $dest
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $dest)
}
function Sync-Tree {
  param([Parameter(Mandatory)] [string]$src,
    [Parameter(Mandatory)] [string]$dst)

  if (-not (Test-Path $src)) { throw "Source not found: $src" }
  if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }

  $args = @($src, $dst, "/MIR", "/E", "/COPY:DAT", "/DCOPY:DAT", "/R:2", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
  Write-Host " > robocopy $($args -join ' ')"
  $p = Start-Process -FilePath "robocopy" -ArgumentList $args -PassThru -WindowStyle Hidden -Wait
  if ($p.ExitCode -le 7) { return }

  Write-Warning "Robocopy  (ExitCode=$($p.ExitCode)). Fallback…"
  Get-ChildItem $dst -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -le 7) { return }

  Copy-Item "$src\*" "$dst\" -Recurse -Force -ErrorAction Stop
}

function New-ServiceStrict {
  param(
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $BinPath,
    [string] $DisplayName = $Name,
    [string] $Description = $Name,
    [string] $Start = "auto",
    [string] $Obj = 'NT AUTHORITY\LocalService'
  )
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($svc) {
    try { Stop-Service $Name -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep 1
    Invoke-Sc ('delete "{0}"' -f $Name) -IgnoreExitCodes 1060
    Start-Sleep 1
  }
  Invoke-Sc ('create "{0}" binPath= {1} start= {2} obj= "{3}" type= own' -f $Name, $BinPath, $Start, $Obj)
  Invoke-Sc ('config "{0}" DisplayName= "{1}"' -f $Name, $DisplayName)
  Invoke-Sc ('description "{0}" "{1}"' -f $Name, $Description)
  if ($Start -eq 'delayed-auto') {
    try { Invoke-Sc ('config "{0}" start= delayed-auto' -f $Name) } catch {}
  }
}

# ============================================
Write-Host "== Installiere GreenKasse =="

Ensure-Dir $PF
Ensure-Dir $PD
Ensure-Dir (Join-Path $PF "Updater")
Ensure-Dir (Join-Path $PF "db")
Ensure-Dir (Join-Path $PD "packages\app\$AppVersion")
Ensure-Dir (Join-Path $PD "packages\pwa\$PwaVersion")
Ensure-Dir (Join-Path $PD "wwwroot")
Ensure-Dir (Join-Path $PD "session")
Ensure-Dir (Join-Path $PD "cache")
Ensure-Dir (Join-Path $PD "logs")
Ensure-Dir (Join-Path $PD "backup")
Ensure-Dir (Join-Path $PD "db\data")

# ================== Updater ==================
if (Test-Path $UpdaterSrc) {
  Write-Host "Kopiere Updater -> $($PF)\Updater"
  Copy-Item "$UpdaterSrc\*" "$PF\Updater\" -Recurse -Force
}

# ================== APP ==================
Write-Host ">>> Installiere App"
$AppTarget = $PF   
if (Test-Path $AppZip) {
  Write-Host "aus ZIP: $AppZip"
  $tmp = Join-Path $env:TEMP ("GK_App_" + [guid]::NewGuid())
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($AppZip, $tmp)

  $exe = Get-ChildItem -Path $tmp -Recurse -Filter $AppExeName -File | Select-Object -First 1
  if (-not $exe) { throw "ZIP hat kein exe datei: $AppExeName" }

  $copyFrom = $exe.Directory.FullName
  Write-Host "copy from: $copyFrom -> $AppTarget"

  robocopy $copyFrom $AppTarget /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -gt 7) { throw "Robocopy error!" }

  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "Src: $AppSrc"
  robocopy $AppSrc $AppTarget /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -gt 7) { throw "Robocopy error!" }
}

Write-Host "APP copy done -> $AppTarget"



# ================== PWA ==================
$PwaTarget    = Join-Path $PD "packages\wwwroot\$PwaVersion"
$PwaCurrentJ  = Join-Path $PD "wwwroot"
Ensure-Dir $PwaTarget

if (Test-Path $PwaZip) {
  Write-Host "PWA aus ZIP -> $PwaTarget"
  $tmp = Join-Path $env:TEMP ("GK_Pwa_" + [guid]::NewGuid())
  Ensure-Dir $tmp
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($PwaZip, $tmp)
  $items = Get-ChildItem $tmp
  $sub   = $items | Where-Object { $_.PSIsContainer } | Select-Object -First 1
  $copyFrom = if ($sub -and $items.Count -eq 1) { $sub.FullName } else { $tmp }
  Sync-Tree $copyFrom $PwaTarget
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "PWA aus Ordner -> $PwaTarget"
  if (-not (Test-Path $PwaSrc)) { throw "PwaSrc fehlt: $PwaSrc" }
  Sync-Tree $PwaSrc $PwaTarget
}

New-Junction $PwaCurrentJ $PwaTarget

# --- MariaDB (BundleRoot\db\mariadb -> $PF\db\mariadb) ---
$MdbSrc = Join-Path $DbSrc "mariadb"
$MdbDst = Join-Path $PF   "db\mariadb"
Ensure-Dir (Join-Path $PF "db")
if (Test-Path $MdbSrc) {
  Write-Host "Synchronisiere MariaDB -> $MdbDst"
  try { Sync-Tree $MdbSrc $MdbDst } catch {
    Write-Warning "MariaDB Sync fehlgeschlagen: $($_.Exception.Message)"
    $DbError = "Sync fehlgeschlagen"
  }
} else {
  Write-Warning "MariaDB-Quelle fehlt: $MdbSrc (DB wird übersprungen)"
  $DbError = "Quelle fehlt"
}

$DbBin   = Join-Path $MdbDst "bin"
$SrvExe  = Join-Path $DbBin "mysqld.exe"
$Mysql   = Join-Path $DbBin 'mysql.exe'
if (-not (Test-Path $SrvExe)) { throw "MariaDB Server EXE fehlt: $SrvExe" }
if (-not (Test-Path $Mysql))  { throw "MariaDB Client EXE fehlt: $Mysql" }

$ShareDir = Join-Path $MdbDst "share"
$ErrFlat  = Join-Path $ShareDir "errmsg.sys"
$ErrLang  = Join-Path $ShareDir "english\errmsg.sys"
if (-not (Test-Path $ErrFlat) -and -not (Test-Path $ErrLang)) {
  throw ("MariaDB 'errmsg.sys' fehlt - weder {0} noch {1}" -f $ErrFlat, $ErrLang)
}
if (-not (Test-Path $ErrFlat) -and (Test-Path $ErrLang)) { Copy-Item $ErrLang $ErrFlat -Force }

# ===================== MariaDB / Verbindungslogik =====================
$DbBin     = Join-Path $PF "db\mariadb\bin"
$BaseDir   = Join-Path $PF "db\mariadb"
$MyIni     = Join-Path $PF "db\my.ini"
$DataDir   = Join-Path $PD "db\data"
$ExportDir = Join-Path $DataDir "export"
$LogFile   = Join-Path $PD "logs\mysqld-init.log"
Ensure-Dir $ExportDir
Ensure-Dir (Split-Path $LogFile)

# Modus ableiten
if ($DbMode -eq 'Auto') {
  if ($DbHost -ne 'localhost' -and $DbHost -ne '127.0.0.1') { $DbMode = 'External' } else { $DbMode = 'Local' }
}

if ($DbMode -eq 'External') {
  if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    Write-Warning 'Externe DB gewaehlt, aber -DbPassword leer. ConnectionString bleibt unveraendert.'
  } else {
    Write-Host ("Externe MariaDB wird verwendet: {0}:{1} / {2}" -f $DbHost, $DbPort, $DbName)
  }
} else {
  cmd /c icacls "$DataDir" /grant "*S-1-5-19:(OI)(CI)M" /T | Out-Null
  cmd /c icacls "$ExportDir" /grant "*S-1-5-19:(OI)(CI)M" /T | Out-Null

  $BundleMyIni = Join-Path $DbSrc 'my.ini'
  if (Test-Path $BundleMyIni) {
    Copy-Item $BundleMyIni $MyIni -Force
  } else {
    $iniContent = @"
[mysqld]
basedir=$BaseDir
datadir=$DataDir
port=$DbPort
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
secure-file-priv=$ExportDir
lc_messages_dir=$BaseDir\share
lc_messages=en_US
log_error=$LogFile
innodb_flush_log_at_trx_commit=1
sync_binlog=1
sql_mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION
skip-name-resolve=1
"@
    Set-ContentUtf8NoBom -Path $MyIni -Value $iniContent
  }

  $ini = Get-Content $MyIni -Raw
  $ini = $ini.Replace('{app}\db\mariadb', $BaseDir)
  $ini = $ini.Replace('{app}\db\data',     $DataDir)
  if ($ini -match 'secure-file-priv\s*=') {
    $ini = $ini -replace 'secure-file-priv\s*=\s*.*', ("secure-file-priv={0}" -f $ExportDir)
  } else {
    $ini += "`r`nsecure-file-priv=$ExportDir"
  }
  if ($ini -notmatch 'lc_messages_dir\s*=') {
    $ini += "`r`nlc_messages_dir=$BaseDir\share`r`nlc_messages=en_US"
  }
  if ($ini -notmatch 'log_error\s*=') {
    $ini += "`r`nlog_error=$LogFile"
  }
  Set-ContentUtf8NoBom -Path $MyIni -Value $ini

  $head = ([IO.File]::ReadAllBytes($MyIni)[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
  if ($head -ne '5B 6D 79 73 71 6C 64 5D') { throw "my.ini invalid header (BOM/whitespace?): $head" }

  $SrvExe = if (Test-Path (Join-Path $DbBin 'mariadbd.exe')) {
    Join-Path $DbBin 'mariadbd.exe'
  } else { Join-Path $DbBin 'mysqld.exe' }
  $Mysql  = Join-Path $DbBin 'mysql.exe'

  if (-not (Test-Path (Join-Path $BaseDir 'share\errmsg.sys'))) {
    Write-Warning "MariaDB 'share\errmsg.sys' nem található: $BaseDir\share\errmsg.sys."
  }

  $needInit = ((Get-ChildItem $DataDir -Force | Measure-Object).Count -eq 0 -or -not (Test-Path (Join-Path $DataDir 'mysql')))

  if ($needInit) {
    Write-Host "Lokales DataDir leer/inkomplett -> Initialisierung"

    $ErrFlat = Join-Path $ShareDir "errmsg.sys"
    $ErrLang = Join-Path $ShareDir "english\errmsg.sys"
    if (-not (Test-Path $ErrFlat) -and (Test-Path $ErrLang)) { Copy-Item $ErrLang $ErrFlat -Force }

    Get-ChildItem $DataDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $InitIni = Join-Path $PD 'db\my.init.ini'
    $InitIniText = @"
[mysqld]
basedir=$BaseDir
datadir=$DataDir
lc_messages_dir=$ShareDir
lc_messages=en_US
"@
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($InitIni, $InitIniText, $enc)

    $InitTool = Join-Path $DbBin 'mariadb-install-db.exe'
    $UseInstallDb = Test-Path $InitTool
    if (-not $UseInstallDb) {
      $MySqld = Join-Path $DbBin 'mysqld.exe'
      if (-not (Test-Path $MySqld)) { throw "mysqld.exe nicht gefunden: $MySqld" }
    }

    $LogFile = Join-Path $PD "logs\mysqld-init.log"
    if ($UseInstallDb) {
      $InitToolQ = '"' + $InitTool + '"'
      $InitArgs  = @("--defaults-file=$InitIni") -join ' '
      Write-Host " > $InitToolQ $InitArgs"
      & cmd /c "$InitToolQ $InitArgs 1>> `"$LogFile`" 2>&1"
    } else {
      $MySqldQ = '"' + $MySqld + '"'
      $InitArgs = @(
        "--defaults-file=$InitIni",
        "--basedir=$BaseDir",
        "--datadir=$DataDir",
        "--initialize-insecure"
      ) -join ' '
      Write-Host " > $MySqldQ $InitArgs"
      & cmd /c "$MySqldQ $InitArgs 1>> `"$LogFile`" 2>&1"
    }

    if ($LASTEXITCODE -ne 0) {
      Write-Host "---- tail of mysqld-init.log ----"
      Write-Warning "Lokale MariaDB-Initialisierung fehlgeschlagen."
      Get-Content $LogFile -Tail 200 -ErrorAction SilentlyContinue | Write-Host
    }
    Write-Host "Initialize OK (ExitCode=0)"

    $FinalIni = @"
[mysqld]
basedir=$BaseDir
datadir=$DataDir
port=$DbPort
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
secure-file-priv=$ExportDir
lc_messages_dir=$ShareDir
lc_messages=en_US
log_error=$LogFile
innodb_flush_log_at_trx_commit=1
sync_binlog=1
sql_mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION
skip-name-resolve=1
"@
    [IO.File]::WriteAllText($MyIni, $FinalIni, $enc)

  } else {
    Write-Host "Lokales DataDir vollständig -> Initialisierung wird übersprungen"
  }

  Invoke-Sc ('delete "{0}"' -f $SvcDb) -IgnoreExitCodes 1060
  $BinPathForSc = ('"\"{0}\" --defaults-file=\"{1}\" --port={2}"' -f $SrvExe, $MyIni, $DbPort)
  Invoke-Sc ('create "{0}" binPath= {1} start= auto type= own obj= "NT AUTHORITY\LocalService"' -f $SvcDb, $BinPathForSc)
  Invoke-Sc ('config "{0}" DisplayName= "{0}"' -f $SvcDb)
  Invoke-Sc ('description "{0}" "GreenKasse MariaDB (local)"' -f $SvcDb)
  Invoke-Sc ('start "{0}"' -f $SvcDb)
  Start-Sleep 3

  if ($needInit -or -not $DbPreserveUsers) {
    if ([string]::IsNullOrWhiteSpace($DbPassword)) { $DbPassword = Get-StrongPassword 24 }
    Write-Host "Benutzer/Schema initialisieren (lokal)"
    & $Mysql "-u" "root" "-e" "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DbPassword'; FLUSH PRIVILEGES;" | Out-Null
    & $Mysql "-u" "root" "-p$DbPassword" "-e" "CREATE DATABASE IF NOT EXISTS $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | Out-Null
    & $Mysql "-u" "root" "-p$DbPassword" "-e" "CREATE USER IF NOT EXISTS '$DbUser'@'localhost' IDENTIFIED BY '$DbPassword';" | Out-Null
    & $Mysql "-u" "root" "-p$DbPassword" "-e" "GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'localhost'; FLUSH PRIVILEGES;" | Out-Null

    if (Test-Path $Schema) {
      Write-Host "Schema import: $Schema"
      & cmd /c "`"$Mysql`" -u $DbUser -p$DbPassword $DbName < `"$Schema`""
      if ($LASTEXITCODE -ne 0) { Write-Warning "Schema import failed (exit $LASTEXITCODE)" }
    }
    if (Test-Path $Seed) {
      Write-Host "Seed import: $Seed"
      & cmd /c "`"$Mysql`" -u $DbUser -p$DbPassword $DbName < `"$Seed`""
      if ($LASTEXITCODE -ne 0) { Write-Warning "Seed import failed (exit $LASTEXITCODE)" }
    }

  } else {
    Write-Host "DbPreserveUsers aktiv & Data vorhanden -> Benutzer/Schema werden NICHT veraendert"
  }

  $DbHost = 'localhost'
  $DbPort = 3307
}

# ===================== appsettings.json =====================
$AppSettings = Join-Path $PF "appsettings.json"
if (-not (Test-Path $AppSettings)) { throw "appsettings.json nicht gefunden: $AppSettings" }

$json = Get-Content $AppSettings -Raw | ConvertFrom-Json
function Ensure-Section([object]$root, [string]$name) {
  if (-not ($root.PSObject.Properties.Name -contains $name)) {
    $root | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{})
  }
}

$json.WebRoot = "C:\\ProgramData\\GreenKasse\\wwwroot"

Ensure-Section $json 'Paths'
$pathsWanted = @{
  BasePath = "C:\\ProgramData\\GreenKasse\\"
  Session  = "C:\\ProgramData\\GreenKasse\\session"
  Cache    = "C:\\ProgramData\\GreenKasse\\cache"
  Packages = "C:\\ProgramData\\GreenKasse\\packages"
  Content  = "C:\\ProgramData\\GreenKasse\\content"
}
foreach ($k in $pathsWanted.Keys) {
  if ($json.Paths.PSObject.Properties.Name -contains $k) { $json.Paths.$k = $pathsWanted[$k] }
  else { $json.Paths | Add-Member -NotePropertyName $k -NotePropertyValue $pathsWanted[$k] }
}

Ensure-Section $json 'ConnectionStrings'
if ($DbMode -eq 'External') {
  if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    Write-Warning 'Externe DB gewaehlt, aber -DbPassword leer. ConnectionString bleibt unveraendert.'
  } else {
    $json.ConnectionStrings.MariaDb = "Server=$DbHost;Port=$DbPort;Database=$DbName;User=$DbUser;Password=$DbPassword;TreatTinyAsBoolean=true;"
  }
} else {
  $json.ConnectionStrings.MariaDb = "Server=$DbHost;Port=$DbPort;Database=$DbName;User=$DbUser;Password=$DbPassword;TreatTinyAsBoolean=true;"
}
$json | ConvertTo-Json  | Set-Content $AppSettings -Encoding UTF8

# ===================== HTTP URL & Firewall =====================
$Url = "http://+:$Port/"
Add-UrlAcl -url $Url -user "NT AUTHORITY\LOCAL SERVICE"
Add-Firewall -name "GreenKasse $Port" -port $Port

# ===================== (App + Updater) =====================
StopAndDelete-Service $SvcApp
StopAndDelete-Service $SvcUpd

# App service – PONTOS PATHOK!
$AppExeFull     = Join-Path $PF $AppExeName
$AppContentRoot =  $PF
if (-not (Test-Path $AppExeFull)) { throw "App EXE fehlt: $AppExeFull" }

$AppBinPath = ('"{0}" --contentRoot "{1}"' -f $AppExeFull, $AppContentRoot)
New-ServiceStrict -Name $SvcApp -BinPath $AppBinPath -DisplayName "GreenKasse App" -Description "GreenKasse .NET App" -Start "auto" -Obj 'NT AUTHORITY\LocalService'
Invoke-Sc ('failure "{0}" reset= 86400 actions= restart/5000' -f $SvcApp)
Invoke-Sc ('start "{0}"' -f $SvcApp)

# Updater
$UpdaterFull = Join-Path $PF "Updater\$UpdaterExe"
if (-not (Test-Path $UpdaterFull)) { throw "Updater EXE fehlt: $UpdaterFull" }
$UpdBinPath = if ([string]::IsNullOrWhiteSpace($UpdaterArgs)) { ('"{0}"' -f $UpdaterFull) } else { ('"{0}" {1}' -f $UpdaterFull, $UpdaterArgs) }
$svcUpdArgs = @{
  Name        = $SvcUpd
  BinPath     = $UpdBinPath
  DisplayName = "GreenKasse Updater"
  Description = "GreenKasse Updater"
  Start       = "delayed-auto"
  Obj         = 'NT AUTHORITY\LocalService'
}
New-ServiceStrict @svcUpdArgs
Invoke-Sc ('failure "{0}" reset= 86400 actions= restart/5000' -f $SvcUpd)
Invoke-Sc ('start "{0}"' -f $SvcUpd)

# ===================== DONE =====================
Write-Host "== GreenKasse ist installiert =="
Write-Host ("URL: http://localhost:{0}/" -f $Port)
Write-Host ("PWA: {0}" -f (Join-Path $PD "wwwroot"))
Write-Host ("App: {0}" -f (Join-Path $PF "App"))

# ---- PWA Auto-Start im App-Fenster (Edge/Chrome) ----
$OpenUrl = "http://localhost:$Port/"
$ok = $false
for ($i=0; $i -lt 20; $i++) {
  try { Invoke-WebRequest -Uri $OpenUrl -UseBasicParsing -TimeoutSec 2 | Out-Null; $ok = $true; break }
  catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ok) { Write-Warning "Backend noch nicht erreichbar, versuche trotzdem Browser-Start" }

$edge   = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"

if (-not (Start-AppWindow $edge $OpenUrl) -and -not (Start-AppWindow $chrome $OpenUrl)) {
  Start-Process $OpenUrl | Out-Null
}

Write-Host "==== Installation abgeschlossen! ====" -ForegroundColor Green
Write-Host ("Web App URL: http://localhost:{0}/" -f $Port)
Write-Host ("PWA Pfad:   {0}" -f (Join-Path $PD 'wwwroot'))
Write-Host ("App Pfad:   {0}" -f (Join-Path $PF 'App'))
