@echo off
setlocal
set "BASE=%~dp0..\db"
set "BIN=%BASE%\mariadb\bin"
"%BIN%\mysqladmin.exe" -u root -p shutdown
