@echo off

if not defined NAOJI_KEEP_WINDOW (
  set "NAOJI_KEEP_WINDOW=1"
  start "SSVEP Windows Launcher" cmd /k ""%~f0" %*"
  exit /b
)

setlocal
chcp 65001 >nul 2>nul
cd /d "%~dp0"

set "SCRIPT=%~dp0launcher.py"
set "SERVER=%~dp0ssvep_server.py"
set "LOG_DIR=%~dp0logs"
set "LOG_FILE=%LOG_DIR%\start_windows.log"
set "TEMP_LOG_FILE=%TEMP%\naoji_start_windows.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
>> "%LOG_FILE%" echo. 2>nul
if errorlevel 1 set "LOG_FILE=%TEMP_LOG_FILE%"
set "NAOJI_LOG_FILE=%LOG_FILE%"

call :log ""
call :log "============================================================"
call :log "启动时间：%DATE% %TIME%"
call :log "工作目录：%CD%"
call :log "日志文件：%LOG_FILE%"
call :log "启动参数：%*"

if not exist "%SCRIPT%" (
  call :log ""
  call :log "未找到 launcher.py，请确认 start_windows.bat 和 launcher.py 在同一个目录。"
  set "EXIT_CODE=1"
  goto end
)

if not exist "%SERVER%" (
  call :log ""
  call :log "未找到 ssvep_server.py，请确认 start_windows.bat 和服务端文件在同一个目录。"
  set "EXIT_CODE=1"
  goto end
)

set "PYTHON_BIN="
set "PYTHON_LABEL="

if exist "%~dp0.venv\Scripts\python.exe" (
  "%~dp0.venv\Scripts\python.exe" -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_BIN=%~dp0.venv\Scripts\python.exe"
    set "PYTHON_LABEL=项目虚拟环境"
  )
)

if not defined PYTHON_BIN (
  where py >nul 2>nul
  if not errorlevel 1 (
    py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
    if not errorlevel 1 (
      set "PYTHON_BIN=py -3"
      set "PYTHON_LABEL=py -3"
    )
  )
)

if not defined PYTHON_BIN (
  where python3 >nul 2>nul
  if not errorlevel 1 (
    python3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
    if not errorlevel 1 (
      set "PYTHON_BIN=python3"
      set "PYTHON_LABEL=python3"
    )
  )
)

if not defined PYTHON_BIN (
  where python >nul 2>nul
  if not errorlevel 1 (
    python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
    if not errorlevel 1 (
      set "PYTHON_BIN=python"
      set "PYTHON_LABEL=python"
    )
  )
)

if not defined PYTHON_BIN (
  call :log ""
  call :log "未检测到 Python 3.10 或更高版本。"
  call :log "请安装 Python 3.10+，并在安装时勾选 Add python.exe to PATH。"
  call :log "下载地址: https://www.python.org/downloads/windows/"
  set "EXIT_CODE=1"
  goto end
)

call :log "使用 Python：%PYTHON_LABEL%"
%PYTHON_BIN% "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto end

:end
if not "%EXIT_CODE%"=="0" (
  call :log ""
  call :log "启动失败，错误码 %EXIT_CODE%。"
  call :log "请把这个日志文件发给开发者：%LOG_FILE%"
  pause
  exit /b %EXIT_CODE%
)

call :log "启动脚本已正常结束。"
exit /b %EXIT_CODE%

:log
if "%~1"=="" (
  echo.
  >> "%LOG_FILE%" echo.
) else (
  echo %~1
  >> "%LOG_FILE%" echo %~1
)
exit /b 0
