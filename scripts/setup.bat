@echo off
setlocal enabledelayedexpansion
echo =====================================
echo WSL Instance Setup Script Starting...
echo =====================================

REM Step 1: Terminate instance (ignore errors if it doesn't exist)
echo [1/7] Terminating MyInstance...
wsl --terminate MyInstance

REM Step 2: Unregister instance (ignore errors if not registered)
echo [2/7] Unregistering MyInstance...
wsl --unregister MyInstance

REM Step 3: Copy cloud-init user-data into place
echo [3/7] Copying cloud-init user-data...
if not exist "%USERPROFILE%\.cloud-init" mkdir "%USERPROFILE%\.cloud-init"
copy /Y "%~dp0distros\ubuntu\24.04\user-data" "%USERPROFILE%\.cloud-init\MyInstance.user-data"
IF %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to copy user-data. Exiting.
    exit /b %ERRORLEVEL%
)

REM Step 4: Install Ubuntu 24.04 instance
echo [4/7] Installing Ubuntu-24.04 as MyInstance...
wsl --install Ubuntu-24.04 --name MyInstance --no-launch
IF %ERRORLEVEL% NEQ 0 (
    echo ERROR: WSL install failed. Exiting.
    exit /b %ERRORLEVEL%
)

REM Step 5: Wait for cloud-init to complete
echo [5/7] Waiting for cloud-init to finish...
wsl -d MyInstance --user root -- cloud-init status --wait

REM Step 6: Terminate instance
echo [6/7] Terminating MyInstance after initialization...
wsl --terminate MyInstance

REM Step 7: Launch instance normally
echo [7/7] Launching MyInstance...
wsl -d MyInstance

endlocal
