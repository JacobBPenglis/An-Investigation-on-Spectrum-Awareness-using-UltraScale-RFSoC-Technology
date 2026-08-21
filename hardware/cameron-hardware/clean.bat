@echo off
setlocal

REM Always operate from the repository root
cd /d "%~dp0"

echo ==========================================
echo Vivado Repository Clean
echo ==========================================
echo.
echo The following ignored files/directories will be removed:
echo.

REM Preview what will be deleted
git clean -Xdfn

echo.
set /p CONFIRM="Delete all ignored files above? (y/N): "

if /I not "%CONFIRM%"=="y" (
    echo.
    echo Clean cancelled.
    exit /b 0
)

echo.
echo Cleaning ignored files...
git clean -Xdf

if errorlevel 1 (
    echo.
    echo ERROR: Git clean failed.
    exit /b 1
)

echo.
echo ==========================================
echo Clean completed successfully.
echo ==========================================

endlocal