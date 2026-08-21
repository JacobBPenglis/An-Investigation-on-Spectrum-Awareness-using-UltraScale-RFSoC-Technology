
@echo off
setlocal

REM Always run relative to the repository root
cd /d "%~dp0"

echo ==========================================
echo Building ZCU111 Vivado project
echo ==========================================

REM If Vivado is already in PATH:

set "VIVADO=C:\Xilinx\Vivado\2024.1\bin\vivado.bat"

call "%VIVADO%" -mode batch -source "vivado-source/build_project.tcl"

if errorlevel 1 (
    echo.
    echo ERROR: Vivado build failed.
    exit /b 1
)

echo.
echo ==========================================
echo Vivado build completed successfully
echo ==========================================

endlocal