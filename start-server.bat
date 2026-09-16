@echo off
chcp 65001 >nul
setlocal
title MMORPG 서버

REM ---------------------------------------------------------------------------
REM 더블클릭으로 게임을 띄운다.
REM
REM npm run dev 한 줄이면 되지만, 그 한 줄을 치려면 터미널을 열고 폴더를 찾아
REM 들어가야 한다. 이 파일은 그 과정을 없앤다.
REM
REM vite 가 클라이언트(5173)를 띄우면서 게임 서버(2567)를 같이 올린다
REM (packages/client 의 game-server 플러그인). 그래서 이것 하나면 된다.
REM
REM 파일은 UTF-8(BOM 없음) + CRLF 로 저장한다. 맨 위 chcp 65001 이 있어야
REM 한글이 안 깨진다 - 없으면 CP949 로 읽혀 글자가 뭉갠다.
REM ---------------------------------------------------------------------------

cd /d "%~dp0"

REM Node 가 PATH 에 없을 수 있다 (scripts/dev.cmd 와 같은 이유)
set "PATH=C:\Program Files\nodejs;%PATH%"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [!] Node.js 를 찾을 수 없습니다.
  echo       https://nodejs.org 에서 LTS 를 설치한 뒤 다시 실행하세요.
  echo.
  pause
  exit /b 1
)

for /f "tokens=*" %%v in ('node -v') do set "NODEVER=%%v"

if not exist "node_modules" (
  echo.
  echo   처음 실행이라 패키지를 설치합니다. 몇 분 걸립니다...
  echo.
  call npm install
  if errorlevel 1 (
    echo.
    echo   [!] 설치에 실패했습니다. 위 메시지를 확인하세요.
    pause
    exit /b 1
  )
)

REM 이미 5173 이 물려 있으면 vite 가 다른 포트로 도망간다 - 주소가 달라져 헷갈린다.
REM netstat/findstr 은 전체 경로로 부른다. PATH 앞에 같은 이름의 다른 프로그램이
REM 깔려 있으면(예: Git 의 유닉스 도구) 엉뚱한 게 잡힌다.
"%SystemRoot%\System32\netstat.exe" -ano | "%SystemRoot%\System32\findstr.exe" /c:":5173 " | "%SystemRoot%\System32\findstr.exe" /i "listening" >nul 2>nul
if not errorlevel 1 (
  echo.
  echo   [!] 5173 포트가 이미 쓰이고 있습니다. 서버가 벌써 떠 있는 것 같습니다.
  echo       브라우저에서 http://localhost:5173 을 열어 보세요.
  echo       새로 띄우려면 먼저 그 창을 Ctrl+C 로 끄세요.
  echo.
  pause
  exit /b 1
)

echo.
echo   -- MMORPG 서버 --------------------------
echo     Node          %NODEVER%
echo     게임 화면     http://localhost:5173
echo     게임 서버     ws://localhost:2567
echo     서버 로그     logs\server.log
echo.
echo     끄려면 이 창에서 Ctrl+C 를 두 번 누르거나 창을 닫으세요.
echo   -----------------------------------------
echo.

REM scripts/dev.cmd 를 그대로 쓴다 - Node 경로 보강과 vite 실행이 거기 있고,
REM 넘긴 인자는 vite 로 간다. --open 은 **서버가 준비된 뒤** vite 가 브라우저를 연다.
REM 배치가 직접 열면 아직 안 떠서 "연결할 수 없음" 이 보이므로 이쪽이 맞다.
call "%~dp0scripts\dev.cmd" --open

echo.
echo   서버가 멈췄습니다.
pause
