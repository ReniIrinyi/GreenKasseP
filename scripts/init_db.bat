@echo off
setlocal
set "BASE=%~dp0..\db"
set "BIN=%BASE%\mariadb\bin"
set "DATA=%BASE%\data"
set "CFG=%BASE%\my.ini"
set "EXPORTDIR=%DATA%\export"
set "DBNAME=posdb"
set "APPUSER=posapp"

if not exist "%DATA%" mkdir "%DATA%"
if not exist "%EXPORTDIR%" mkdir "%EXPORTDIR%"

REM 1) init 
"%BIN%\mysqld.exe" --defaults-file="%CFG%" --initialize-insecure || goto :err

REM 2) start server
start "" "%BIN%\mysqld.exe" --defaults-file="%CFG%"
timeout /t 5 >nul

REM 3) 
for /f "usebackq delims=" %%P in (`
  powershell -NoP -C ^
    "$b=New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b);" ^
    "$s=[Convert]::ToBase64String($b).TrimEnd('=').Replace('+','B').Replace('/','A');" ^
    "$s"
`) do set "APPPWD=%%P"

REM 4) root pw + db + user
"%BIN%\mysql.exe" -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%APPPWD%'; FLUSH PRIVILEGES;"
"%BIN%\mysql.exe" -u root -p"%APPPWD%" -e "CREATE DATABASE IF NOT EXISTS %DBNAME% CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
"%BIN%\mysql.exe" -u root -p"%APPPWD%" -e "CREATE USER IF NOT EXISTS '%APPUSER%'@'localhost' IDENTIFIED BY '%APPPWD%';"
"%BIN%\mysql.exe" -u root -p"%APPPWD%" -e "GRANT ALL PRIVILEGES ON %DBNAME%.* TO '%APPUSER%'@'localhost'; FLUSH PRIVILEGES;"

REM 5)
if exist "%~dp0..\schemas\schema.sql" "%BIN%\mysql.exe" -u "%APPUSER%" -p"%APPPWD%" "%DBNAME%" < "%~dp0..\schemas\schema.sql"
if exist "%~dp0..\schemas\seed.sql"   "%BIN%\mysql.exe" -u "%APPUSER%" -p"%APPPWD%" "%DBNAME%" < "%~dp0..\schemas\seed.sql"

REM 6) appsettings.json frissítés 
set "CFGFILE=%~dp0..\app\appsettings.json"
powershell -NoP -C ^
  "$p='%CFGFILE%';" ^
  "$j=Get-Content $p -Raw | ConvertFrom-Json;" ^
  "if(-not $j.ConnectionStrings){$j|Add-Member -NotePropertyName ConnectionStrings -NotePropertyValue (@{})};" ^
  "$j.ConnectionStrings.MariaDb='Server=127.0.0.1;Port=3306;Database=%DBNAME%;User=%APPUSER%;Password=%APPPWD%;TreatTinyAsBoolean=true;';" ^
  "$j|ConvertTo-Json -Depth 12|Set-Content $p -Encoding UTF8"

echo OK - MariaDB inicializalva. user: %APPUSER%
exit /b 0

:err
echo HIBA az inicializalas kozben. KOD: %ERRORLEVEL%
exit /b 1
