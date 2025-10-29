@echo off
setlocal
REM --- Canonical paths relative to BundleRoot/scripts ---
set "ROOT=%~dp0.."
set "BASE=%ROOT%\db"
set "BIN=%BASE%\mariadb\bin"
set "DATA=%ProgramData%\GreenKasse\db\data"
set "SHARE=%BASE%\mariadb\share"
set "INITCFG=%ProgramData%\GreenKasse\db\my.init.ini"
set "FINALCFG=%ProgramFiles(x86)%\GreenKasse\db\my.ini"
set "EXPORTDIR=%DATA%\export"

set "DBPORT=3307"
set "DBNAME=posdb"
set "APPUSER=posapp"

if not exist "%DATA%" mkdir "%DATA%"
if not exist "%EXPORTDIR%" mkdir "%EXPORTDIR%"
if not exist "%ProgramData%\GreenKasse\db" mkdir "%ProgramData%\GreenKasse\db"

REM 0) ensure errmsg.sys present (copy english\errmsg.sys -> flat, if needed)
if exist "%SHARE%\english\errmsg.sys" if not exist "%SHARE%\errmsg.sys" copy "%SHARE%\english\errmsg.sys" "%SHARE%\errmsg.sys" >nul

REM 1) write minimal init INI (no spaces headaches in path)
> "%INITCFG%" (
  echo [mysqld]
  echo basedir=%BASE%\mariadb
  echo datadir=%DATA%
  echo lc_messages_dir=%SHARE%
  echo lc_messages=en_US
)

REM 2) initialize (mysqld only; DO NOT use mariadb-install-db)
"%BIN%\mysqld.exe" --defaults-file="%INITCFG%" --initialize-insecure || goto :err

REM 3) start temporary server on DBPORT with FINALCFG if already written, else INITCFG
set "CFGTOUSE=%FINALCFG%"
if not exist "%CFGTOUSE%" set "CFGTOUSE=%INITCFG%"

start "" "%BIN%\mysqld.exe" --defaults-file="%CFGTOUSE%" --port=%DBPORT%
REM wait a bit
for /l %%i in (1,1,30) do (
  "%BIN%\mysqladmin.exe" -u root ping >nul 2>&1 && goto :db_up
  timeout /t 1 >nul
)
:db_up

REM 4) generate password
for /f "usebackq delims=" %%P in (`
  powershell -NoP -C ^
    "$b=New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b);" ^
    "$s=[Convert]::ToBase64String($b).TrimEnd('=')" ^
    ".Replace('+','B').Replace('/','A');" ^
    "$s"
`) do set "APPPWD=%%P"

REM 5) root pw + db + user (use explicit --port)
"%BIN%\mysql.exe" -u root --port=%DBPORT% -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%APPPWD%'; FLUSH PRIVILEGES;"
"%BIN%\mysql.exe" -u root --port=%DBPORT% -p"%APPPWD%" -e "CREATE DATABASE IF NOT EXISTS %DBNAME% CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
"%BIN%\mysql.exe" -u root --port=%DBPORT% -p"%APPPWD%" -e "CREATE USER IF NOT EXISTS '%APPUSER%'@'localhost' IDENTIFIED BY '%APPPWD%';"
"%BIN%\mysql.exe" -u root --port=%DBPORT% -p"%APPPWD%" -e "GRANT ALL PRIVILEGES ON %DBNAME%.* TO '%APPUSER%'@'localhost'; FLUSH PRIVILEGES;"

REM 6) optional schema/seed
if exist "%ROOT%\db\schemas\schema.sql" "%BIN%\mysql.exe" -u "%APPUSER%" --port=%DBPORT% -p"%APPPWD%" "%DBNAME%" < "%ROOT%\db\schemas\schema.sql"
if exist "%ROOT%\db\schemas\seed.sql"   "%BIN%\mysql.exe" -u "%APPUSER%" --port=%DBPORT% -p"%APPPWD%" "%DBNAME%" < "%ROOT%\db\schemas\seed.sql"

REM 7) write connection string into appsettings.json under BundleRoot/app
set "CFGFILE=%ROOT%\app\appsettings.json"
powershell -NoP -C ^
  "$p='%CFGFILE%';" ^
  "$j=Get-Content $p -Raw | ConvertFrom-Json;" ^
  "if(-not $j.ConnectionStrings){$j|Add-Member -NotePropertyName ConnectionStrings -NotePropertyValue (@{})};" ^
  "$j.ConnectionStrings.MariaDb='Server=127.0.0.1;Port=%DBPORT%;Database=%DBNAME%;User=%APPUSER%;Password=%APPPWD%;TreatTinyAsBoolean=true;';" ^
  "$j|ConvertTo-Json -Depth 12|Set-Content $p -Encoding UTF8"

REM 8) stop temp server cleanly
"%BIN%\mysqladmin.exe" -u root --port=%DBPORT% -p"%APPPWD%" shutdown

echo OK - MariaDB initialisiert. user: %APPUSER%
exit /b 0

:err
echo HIBA az inicializalas kozben. KOD: %ERRORLEVEL%
exit /b 1
