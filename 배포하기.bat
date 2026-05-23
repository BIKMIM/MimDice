@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title MimDice Deploy

echo ================================
echo    MimDice GitHub Deploy
echo ================================
echo.

set "TOC_PATH=%~dp0MimDice.toc"
set "LUA_PATH=%~dp0MimDice.lua"

rem Read current version from TOC (## Version: X.Y.Z)
powershell -NoProfile -Command "$m = Select-String -Path '%TOC_PATH%' -Pattern '^##\s*Version:\s*(\S+)' | Select-Object -First 1; if ($m) { $m.Matches[0].Groups[1].Value | Out-File -Encoding ascii '%TEMP%\mimdice_ver.txt' -NoNewline }"
set CURRENT_VER=
if exist "%TEMP%\mimdice_ver.txt" (
    set /p CURRENT_VER=<"%TEMP%\mimdice_ver.txt"
    del "%TEMP%\mimdice_ver.txt" >nul 2>&1
)
if "%CURRENT_VER%"=="" (
    echo [ERROR] Cannot read version from MimDice.toc
    pause
    exit /b 1
)

rem Suggest next patch version (X.Y.Z -> X.Y.Z+1)
echo %CURRENT_VER%| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [WARN] Current version not SEMVER: %CURRENT_VER%
    set SUGGESTED_VER=%CURRENT_VER%
) else (
    for /f "tokens=1-3 delims=." %%a in ("%CURRENT_VER%") do (
        set /a NEXT_PATCH=%%c + 1
        set SUGGESTED_VER=%%a.%%b.!NEXT_PATCH!
    )
)

rem Show last commit subject
set LAST_COMMIT=
for /f "delims=" %%i in ('git log -1 --format^=%%s 2^>nul') do set LAST_COMMIT=%%i
if not "!LAST_COMMIT!"=="" echo Last deploy  : !LAST_COMMIT!
echo Current ver  : %CURRENT_VER%
echo Next version : !SUGGESTED_VER!
echo.

rem === Version prompt ===
set /p NEW_VER=New version [Enter = !SUGGESTED_VER!]:
if "%NEW_VER%"=="" (
    set NEW_VER=!SUGGESTED_VER!
    echo Use: !NEW_VER!
) else (
    if /i "!NEW_VER:~0,1!"=="v" set NEW_VER=!NEW_VER:~1!
    echo Change: %CURRENT_VER% -^> !NEW_VER!
)

rem Safety: must be X.Y.Z
echo !NEW_VER!| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo.
    echo [ERROR] Version must be X.Y.Z ^(e.g. 1.7.3^). Got: !NEW_VER!
    pause
    exit /b 1
)
echo.

rem === Commit message prompt ===
set /p COMMIT_MSG=Commit message [example: add sound effect / Space = empty]:
if "!COMMIT_MSG!"==" " set COMMIT_MSG=
echo.

echo ================================
echo   Deploy Info
echo ================================
echo   Version : !NEW_VER!
if "!COMMIT_MSG!"=="" (
    echo   Message : v!NEW_VER!
) else (
    echo   Message : v!NEW_VER! !COMMIT_MSG!
)
echo ================================
echo.
echo Deploy?  [Enter] = Yes  /  [Esc] = Cancel
powershell -NoProfile -Command "do { $k=[Console]::ReadKey($true) } until ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape'); if ($k.Key -eq 'Escape') { exit 1 } else { exit 0 }"
if errorlevel 1 (
    echo Cancelled.
    pause
    exit /b 0
)
echo.

rem -- Step 1: Version update (TOC + MimDice.lua header comment)
if "!NEW_VER!"=="%CURRENT_VER%" (
    echo [1/3] No version change - skip
    goto :step2
)

echo [1/3] Updating version files...

rem TOC: "## Version: X.Y.Z"
powershell -NoProfile -Command "$c=(Get-Content '%TOC_PATH%' -Raw -Encoding UTF8) -replace '(?m)^##\s*Version:.*$', '## Version: !NEW_VER!'; [System.IO.File]::WriteAllText('%TOC_PATH%', $c, (New-Object System.Text.UTF8Encoding $false))"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to update TOC
    pause
    exit /b 1
)

rem MimDice.lua header comment: "-- Version        : vX.Y.Z" (들여쓰기 하드코딩 — capture group 회피)
powershell -NoProfile -Command "$c=(Get-Content '%LUA_PATH%' -Raw -Encoding UTF8) -replace '(?m)^--\s*Version\s*:.*$', '-- Version        : v!NEW_VER!'; [System.IO.File]::WriteAllText('%LUA_PATH%', $c, (New-Object System.Text.UTF8Encoding $false))"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to update MimDice.lua
    pause
    exit /b 1
)

echo [1/3] Version updated to !NEW_VER!

:step2
echo.

rem -- Step 2: Git pull + commit
echo [2/3] Git commit...
git pull --rebase --autostash origin main
if errorlevel 1 (
    echo.
    echo [ERROR] Git pull failed. Resolve conflicts then retry.
    pause
    exit /b 1
)
git add .
git status --short
echo.
if "!COMMIT_MSG!"=="" (
    git commit -m "v!NEW_VER!"
) else (
    git commit -m "v!NEW_VER! !COMMIT_MSG!"
)
if errorlevel 1 (
    echo.
    echo [ERROR] Nothing to commit or commit failed.
    pause
    exit /b 1
)
echo [2/3] Commit done
echo.

rem -- Step 3: Push to GitHub
echo [3/3] Pushing to GitHub...
git push origin main
if errorlevel 1 (
    echo.
    echo [ERROR] Push failed. Check network or GitHub access.
    pause
    exit /b 1
)
echo [3/3] Push done
echo.

echo ================================
echo    Done^^!  v!NEW_VER!
echo ================================
echo.
pause
