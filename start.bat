@echo off
REM Cross-platform launcher for SillyTavern Corruption Guard (Windows)
REM Works with PowerShell 5.1 or PowerShell 7+

setlocal

REM Determine which PowerShell to use
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    REM PowerShell 7+ is available
    set PS_EXECUTABLE=pwsh
) else (
    REM Fall back to PowerShell 5.1
    set PS_EXECUTABLE=powershell
)

REM Run the main script
if "%~1"=="" (
    %PS_EXECUTABLE% -File "%~dp0src\ST_VM_Main.ps1"
) else (
    %PS_EXECUTABLE% -File "%~dp0src\ST_VM_Main.ps1" %*
)

endlocal
