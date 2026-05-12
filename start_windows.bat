@echo off
setlocal
cd /d "%~dp0"

set "SCRIPT=%~dp0launcher.py"

where py >nul 2>nul
if %ERRORLEVEL%==0 (
  py -3 "%SCRIPT%" %*
  set "EXIT_CODE=%ERRORLEVEL%"
  goto end
)

where python >nul 2>nul
if %ERRORLEVEL%==0 (
  python "%SCRIPT%" %*
  set "EXIT_CODE=%ERRORLEVEL%"
  goto end
)

echo.
echo 未检测到 Python 3。
echo 请先安装 Python 3.10 或更高版本，并在安装时勾选 "Add python.exe to PATH"。
echo 下载地址: https://www.python.org/downloads/windows/
set "EXIT_CODE=1"

:end
if not "%EXIT_CODE%"=="0" (
  echo.
  echo 启动失败，错误码 %EXIT_CODE%。
  pause
)

exit /b %EXIT_CODE%
