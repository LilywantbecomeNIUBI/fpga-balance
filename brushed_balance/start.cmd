@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo P30 有刷平衡车 - 独立工程
echo 1 离线演示（默认，不打开串口）
echo 2 实机控制台（仍需页面中选择串口并连接）
echo 3 M2接线 GMR 观察版构建（不下载）
echo 4 M2接线 GMR 驱动版构建（不下载）
set /p BB_CHOICE=选择 [1]:
if "%BB_CHOICE%"=="2" (python tools\run.py --live & goto done)
if "%BB_CHOICE%"=="3" (python tools\build.py --profile observe & goto done)
if "%BB_CHOICE%"=="4" (python tools\build.py --profile drive & goto done)
python tools\run.py --demo
:done
if errorlevel 1 pause
