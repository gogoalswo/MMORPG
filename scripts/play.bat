@echo off
rem ============================================================
rem  PC 에서 최신 빌드를 실제로 플레이한다 (윈도우)
rem
rem  고도를 "설치" 하지 않는다 — zip 을 받아 exe 하나만 C:\godot 에
rem  남기고 zip 은 지운다. 두 번째 실행부터는 받지 않는다.
rem
rem    scripts\play.bat        최신 코드 받아서 게임 실행
rem    scripts\play.bat edit   편집기로 열기
rem
rem  둘 곳을 바꾸려면:  set GODOT_DIR=D:\godot  후 실행
rem  자세한 건 docs/features/godot-migration.md 의 "PC 에서 플레이한다"
rem ============================================================
setlocal
chcp 65001 >nul

set "GODOT_VERSION=4.7.2"
if "%GODOT_DIR%"=="" set "GODOT_DIR=C:\godot"
set "GODOT_EXE=%GODOT_DIR%\godot.exe"

pushd "%~dp0.."
set "ROOT=%CD%"
popd

if not exist "%ROOT%\godot\project.godot" (
  echo 저장소 안에서 실행해야 한다 — %ROOT%\godot\project.godot 이 없다
  pause
  exit /b 1
)

rem ---- 1. 고도 준비 — 없을 때만 받는다 -----------------------
rem  라벨(goto)을 쓰지 않는다 — 이 저장소는 .gitattributes 로 LF 를 못 박는데,
rem  LF 짜리 배치에서 goto 가 어긋나는 윈도우가 있다. 블록 하나로 끝낸다.
rem  블록 안에서 set 한 값은 %...% 로 못 읽으므로(파싱 시점에 전개된다)
rem  zip 경로는 변수로 두지 않고 그대로 쓴다.
if exist "%GODOT_EXE%" echo [1/5] 고도 %GODOT_VERSION% — 이미 있다 ^(%GODOT_EXE%^)

if not exist "%GODOT_EXE%" (
  echo [1/5] 고도 %GODOT_VERSION% 를 받는다 ^(약 86MB, 처음 한 번만^)
  if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"

  curl -fL --progress-bar -o "%TEMP%\godot-%GODOT_VERSION%.zip" "https://downloads.godotengine.org/?version=%GODOT_VERSION%&flavor=stable&slug=win64.exe.zip&platform=windows.64"
  if errorlevel 1 (
    echo       받기 실패 — 인터넷 연결을 확인한다
    del /q "%TEMP%\godot-%GODOT_VERSION%.zip" 2>nul
    pause
    exit /b 1
  )

  rem 윈도우 10 부터 tar 가 zip 을 푼다. 없으면 파워셸로.
  tar -xf "%TEMP%\godot-%GODOT_VERSION%.zip" -C "%GODOT_DIR%" 2>nul
  if errorlevel 1 powershell -NoProfile -Command "Expand-Archive -Force '%TEMP%\godot-%GODOT_VERSION%.zip' '%GODOT_DIR%'"

  rem 쓰는 건 exe 하나뿐이다 — 이름을 바꾸고 나머지와 zip 은 지운다
  move /y "%GODOT_DIR%\Godot_v%GODOT_VERSION%-stable_win64.exe" "%GODOT_EXE%" >nul
  del /q "%GODOT_DIR%\Godot_v%GODOT_VERSION%-stable_win64_console.exe" 2>nul
  del /q "%TEMP%\godot-%GODOT_VERSION%.zip" 2>nul

  if not exist "%GODOT_EXE%" (
    echo       압축은 풀렸는데 godot.exe 가 없다 — %GODOT_DIR% 를 확인한다
    pause
    exit /b 1
  )
  echo       -^> %GODOT_EXE% ^(zip 은 지웠다^)
)

rem ---- 2. 최신 코드 — 지금 체크아웃된 브랜치를 받는다 ---------
echo [2/5] 최신 코드를 받는다
where git >nul 2>nul
if errorlevel 1 (
  echo       git 이 없다 — 지금 있는 코드로 실행한다
) else (
  git -C "%ROOT%" pull --ff-only
  if errorlevel 1 echo       pull 실패 — 지금 있는 코드로 실행한다
)

rem ---- 3. 에셋 — public/assets 에서 복사한다 ------------------
rem  npm run sync:godot 과 달리 텍스처를 512 로 줄이지 않는다.
rem  줄이는 건 폰 pck 용량 때문이고, PC 는 원본이 낫다 (Node 도 필요 없다).
echo [3/5] 에셋을 godot\assets 로 복사한다
for %%d in (models fonts ground) do if not exist "%ROOT%\godot\assets\%%d" mkdir "%ROOT%\godot\assets\%%d"
xcopy /D /Y /Q "%ROOT%\public\assets\models\varco_knight.glb"     "%ROOT%\godot\assets\models\" >nul
xcopy /D /Y /Q "%ROOT%\public\assets\models\varco_ogre1.glb"      "%ROOT%\godot\assets\models\" >nul
xcopy /D /Y /Q "%ROOT%\public\assets\fonts\NotoSansKR-subset.ttf" "%ROOT%\godot\assets\fonts\"  >nul
xcopy /D /Y /Q "%ROOT%\public\assets\textures\ground_*.ktx2"      "%ROOT%\godot\assets\ground\" >nul

rem ---- 4. 임포트 — 캐시가 없으면 스크립트가 클래스를 못 찾는다 -
echo [4/5] 에셋을 임포트한다 ^(처음 한 번은 몇 분 걸린다^)
"%GODOT_EXE%" --headless --path "%ROOT%\godot" --import >nul 2>&1
if errorlevel 1 echo       임포트가 깨끗하지 않다 — 그래도 띄워 본다

rem ---- 5. 실행 -----------------------------------------------
if /i "%~1"=="edit" (
  echo [5/5] 편집기로 연다 — F5 로 실행한다
  "%GODOT_EXE%" --editor --path "%ROOT%\godot"
) else (
  echo [5/5] 게임을 띄운다 — 창을 닫으면 끝난다
  "%GODOT_EXE%" --path "%ROOT%\godot"
)
rem 더블클릭으로 띄웠을 때 오류 메시지가 스쳐 지나가지 않게
if errorlevel 1 pause

endlocal
