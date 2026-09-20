@echo off
rem ============================================================
rem  Run the latest build on a Windows PC.
rem
rem  Godot is not "installed": the zip is downloaded, only
rem  godot.exe is kept in C:\godot, and the zip is deleted.
rem  Later runs skip the download entirely.
rem
rem    scripts\play.bat        pull latest code and play
rem    scripts\play.bat edit   open the Godot editor instead
rem    set GODOT_DIR=D:\godot  put the engine somewhere else
rem
rem  ASCII only, and no chcp: cmd reads a .bat in the console
rem  code page, so UTF-8 Korean text made it lose its read
rem  position and run garbage like 'orlevel' (2026-09-17).
rem  No goto/labels either - see docs/features/godot-migration.md
rem  section "PC play" for the Korean notes.
rem ============================================================
setlocal

set "GODOT_VERSION=4.7.2"
if "%GODOT_DIR%"=="" set "GODOT_DIR=C:\godot"
set "GODOT_EXE=%GODOT_DIR%\godot.exe"

pushd "%~dp0.."
set "ROOT=%CD%"
popd

if not exist "%ROOT%\godot\project.godot" (
  echo Run this from inside the repo - %ROOT%\godot\project.godot is missing
  pause
  exit /b 1
)

rem ---- 1. the engine, downloaded only when missing -----------
if exist "%GODOT_EXE%" echo [1/5] Godot %GODOT_VERSION% - already here ^(%GODOT_EXE%^)

if not exist "%GODOT_EXE%" (
  echo [1/5] Downloading Godot %GODOT_VERSION% - 86MB, first run only
  if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"

  curl -fL --progress-bar -o "%TEMP%\godot-%GODOT_VERSION%.zip" "https://downloads.godotengine.org/?version=%GODOT_VERSION%&flavor=stable&slug=win64.exe.zip&platform=windows.64"
  if errorlevel 1 (
    echo       download failed - check your internet connection
    del /q "%TEMP%\godot-%GODOT_VERSION%.zip" 2>nul
    pause
    exit /b 1
  )

  rem tar ships with Windows 10+ and handles zip; PowerShell is the fallback
  tar -xf "%TEMP%\godot-%GODOT_VERSION%.zip" -C "%GODOT_DIR%" 2>nul
  if errorlevel 1 powershell -NoProfile -Command "Expand-Archive -Force '%TEMP%\godot-%GODOT_VERSION%.zip' '%GODOT_DIR%'"

  rem only the one exe is kept; console build and zip are deleted
  move /y "%GODOT_DIR%\Godot_v%GODOT_VERSION%-stable_win64.exe" "%GODOT_EXE%" >nul
  del /q "%GODOT_DIR%\Godot_v%GODOT_VERSION%-stable_win64_console.exe" 2>nul
  del /q "%TEMP%\godot-%GODOT_VERSION%.zip" 2>nul

  if not exist "%GODOT_EXE%" (
    echo       unpacked but godot.exe is missing - check %GODOT_DIR%
    pause
    exit /b 1
  )
  echo       -^> %GODOT_EXE% ^(zip deleted^)
)

rem ---- 2. latest code on the branch you have checked out -----
echo [2/5] Pulling latest code
where git >nul 2>nul
if errorlevel 1 (
  echo       git not found - running with the code you have
) else (
  git -C "%ROOT%" pull --ff-only
  if errorlevel 1 echo       pull failed - running with the code you have
)

rem ---- 3. assets: mirror the whole public\assets tree ---------
rem  One line on purpose. Listing folders by hand is how icons\
rem  and ui\ got missed - they were simply absent on a PC run and
rem  the window came up as red errors and plain text (2026-09-19).
rem  A new asset folder now needs no edit here.
rem
rem  Folder names match on both sides, so this is a plain mirror.
rem  "npm run sync:godot" copies less and shrinks model textures to
rem  512px - that is to keep the phone pck small. A PC does not
rem  care, and copying everything needs no Node and no sharp.
rem  /D skips files that are already up to date.
rem
rem  Side effect: model textures stay at 1024px here, so running
rem  "npm run test:godot" right after this makes model_test say
rem  "texture is 1024px". That guard is there to keep the phone
rem  pck small - run "npm run sync:godot" before testing.
echo [3/5] Copying assets to godot\assets
if not exist "%ROOT%\godot\assets" mkdir "%ROOT%\godot\assets"
xcopy /E /I /D /Y /Q "%ROOT%\public\assets" "%ROOT%\godot\assets" >nul

rem ---- 4. import: without the cache class_name lookups fail ---
echo [4/5] Importing assets - the first run takes a few minutes
"%GODOT_EXE%" --headless --path "%ROOT%\godot" --import >nul 2>&1
if errorlevel 1 echo       import reported problems - trying to run anyway

rem ---- 5. run ------------------------------------------------
if /i "%~1"=="edit" (
  echo [5/5] Opening the editor - press F5 to play
  "%GODOT_EXE%" --editor --path "%ROOT%\godot"
) else (
  echo [5/5] Starting the game - close the window to quit
  "%GODOT_EXE%" --path "%ROOT%\godot"
)

rem keep the window open when double-clicked and something failed
if errorlevel 1 pause

endlocal
