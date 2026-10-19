@echo off
REM ============================================================
REM  Starts the UC Lost & Found site on this Windows computer.
REM  No Docker needed. Just double-click this file.
REM  The first run takes a minute while it installs Flask.
REM ============================================================
cd /d "%~dp0"
title UC Lost and Found - local site

REM Use the Python launcher (py) if it exists, otherwise "python".
where py >nul 2>nul
if %errorlevel%==0 (set PY=py -3) else (set PY=python)

if not exist venv\Scripts\python.exe (
    echo Setting up for the first time, this takes about a minute...
    %PY% -m venv venv || goto nopython
)

echo Checking requirements...
venv\Scripts\python.exe -m pip install --quiet --disable-pip-version-check -r requirements.txt || goto piperror

echo.
echo  ==========================================================
echo   The site is running at:  http://localhost:5000
echo   Your browser will open in a few seconds.
echo   Keep this window open while you use the site.
echo   To stop the site, close this window or press Ctrl+C.
echo  ==========================================================
echo.

REM Open the browser once the site has had a few seconds to start.
start "" powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 4; Start-Process 'http://localhost:5000'"

venv\Scripts\python.exe app.py
echo.
echo The site has stopped.
pause
goto :eof

:nopython
echo.
echo Python is not installed yet.
echo Install it from https://www.python.org/downloads/
echo On the first installer screen, tick "Add python.exe to PATH".
echo Then double-click this file again.
pause
goto :eof

:piperror
echo.
echo Installing the requirements failed. Check your internet connection,
echo or copy the error above and send it to Claude.
pause
goto :eof
