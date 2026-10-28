@echo off
chcp 65001 >nul
where py >nul 2>nul
if errorlevel 1 (
  python "%~dp0..\..\tools\manual.py" %*
) else (
  py -3 "%~dp0..\..\tools\manual.py" %*
)
if errorlevel 1 pause
