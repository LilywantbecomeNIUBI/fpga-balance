@echo off
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  python tools\run.py build-observe
) else (
  py -3 tools\run.py build-observe
)
pause
