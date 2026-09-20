@echo off
title Versus Multiplayer Server
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
	echo Node.js is required to run the server. Get it from https://nodejs.org ^(LTS version^), then run this again.
	pause
	exit /b 1
)

rem Extra options can be passed on the command line, e.g.
rem    start-server.bat --port 7777 --password mysecret
node server.js %*

echo.
echo The server stopped.
pause
