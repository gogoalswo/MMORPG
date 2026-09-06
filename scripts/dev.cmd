@echo off
REM Claude Code 세션이 Node 설치 이전 PATH를 물고 있어서 임시로 붙여준다.
REM (새 터미널에서는 그냥 `npm run dev` 로 실행하면 된다)
set "PATH=C:\Program Files\nodejs;%PATH%"
cd /d "%~dp0..\packages\client"
node "..\..\node_modules\vite\bin\vite.js" %*
