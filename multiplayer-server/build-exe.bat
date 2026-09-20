@echo off
rem Builds dist\versus-server.exe: a standalone copy of the server that runs without Node.js installed.
rem Needs Node.js 20+ and internet access (downloads the small "postject" tool through npx).
cd /d "%~dp0"
if not exist dist mkdir dist
node --experimental-sea-config sea-config.json || goto :fail
for /f "delims=" %%F in ('where node') do (
	set NODE_EXE=%%F
	goto :copy
)
:copy
copy /y "%NODE_EXE%" dist\versus-server.exe >nul
call npx --yes postject dist\versus-server.exe NODE_SEA_BLOB sea-prep.blob --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 --overwrite || goto :fail
echo.
echo Done: dist\versus-server.exe
exit /b 0
:fail
echo Build failed.
exit /b 1
