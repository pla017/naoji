@echo off
setlocal
chcp 65001 >nul 2>nul
cd /d "%~dp0"

set "SCRIPT=%~dp0launcher.py"
set "SERVER=%~dp0ssvep_server.py"

if not exist "%SCRIPT%" (
  echo.
  echo 未找到 launcher.py，请确认 start_windows.bat 和 launcher.py 在同一个目录。
  set "EXIT_CODE=1"
  goto end
)

if not exist "%SERVER%" (
  echo.
  echo 未找到 ssvep_server.py，请确认 start_windows.bat 和服务端文件在同一个目录。
  set "EXIT_CODE=1"
  goto end
)

where py >nul 2>nul
if not errorlevel 1 (
  py -3 --version >nul 2>nul
  if not errorlevel 1 goto run_py
)

where python3 >nul 2>nul
if not errorlevel 1 (
  python3 --version >nul 2>nul
  if not errorlevel 1 goto run_python3
)

where python >nul 2>nul
if not errorlevel 1 (
  python --version >nul 2>nul
  if not errorlevel 1 goto run_python
)

echo.
echo 未检测到 Python 3。
echo 请先安装 Python 3.10 或更高版本，并在安装时勾选 "Add python.exe to PATH"。
echo 下载地址: https://www.python.org/downloads/windows/
set "EXIT_CODE=1"
goto end

:run_py
py -3 "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto end

:run_python3
python3 "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto end

:run_python
python "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto end

:end
if not "%EXIT_CODE%"=="0" (
  echo.
  echo 启动失败，错误码 %EXIT_CODE%。
  pause
)

exit /b %EXIT_CODE%
