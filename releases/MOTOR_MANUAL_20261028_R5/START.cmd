@echo off
chcp 65001 >nul
where py >nul 2>nul
if errorlevel 1 (
  python "%~dp0..\..\tools\manual.py" --release MOTOR_MANUAL_20261028_R5 %*
) else (
  py -3 "%~dp0..\..\tools\manual.py" --release MOTOR_MANUAL_20261028_R5 %*
)
if errorlevel 1 pause
