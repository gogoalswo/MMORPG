@echo off
rem ============================================================
rem  One-file launcher for a PC that has no copy of the repo yet.
rem  Put it anywhere (Desktop is fine) and double-click it.
rem
rem    1. no git     -> installs Git with winget (asks for consent)
rem    2. no clone   -> clones into C:\MMORPG
rem    3. switches to main, then hands over to scripts\play.bat
rem       (engine download, pull, assets, import, run)
rem
rem    launcher.bat edit       open the Godot editor instead
rem    set MMORPG_DIR=D:\MMORPG  clone somewhere else
rem
rem  ASCII only, no goto/labels, stored as CRLF even on GitHub
rem  (.gitattributes: -text) so the raw download works as is.
rem  Korean notes: docs/features/godot-migration.md "PC play".
rem ============================================================
setlocal

set "REPO_URL=https://github.com/gogoalswo/MMORPG.git"
if "%MMORPG_DIR%"=="" set "MMORPG_DIR=C:\MMORPG"

rem ---- git: a fresh winget install is not on PATH yet --------
where git >nul 2>nul
if errorlevel 1 if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
where git >nul 2>nul
if errorlevel 1 (
  echo [git] Not found - installing Git with winget
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
)
where git >nul 2>nul
if errorlevel 1 (
  echo [git] Still no git. Install it from https://git-scm.com and run this again.
  pause
  exit /b 1
)

rem ---- clone once, then always stay on main -------------------
if not exist "%MMORPG_DIR%\.git" (
  echo [repo] Cloning into %MMORPG_DIR%
  git clone "%REPO_URL%" "%MMORPG_DIR%"
  if errorlevel 1 (
    echo [repo] Clone failed - check your internet connection
    pause
    exit /b 1
  )
)

git -C "%MMORPG_DIR%" checkout main
if errorlevel 1 echo [repo] Could not switch to main - local changes? Running the current branch.

rem ---- the rest is play.bat's job -----------------------------
call "%MMORPG_DIR%\scripts\play.bat" %*

endlocal
