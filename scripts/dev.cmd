@echo off
REM Claude Code session can hold a PATH from before Node was installed.
REM (In a normal terminal just run `npm run dev`.)
REM Keep this file ASCII-only: cmd garbles non-ASCII lines under CP437/CP949.
set "PATH=C:\Program Files\nodejs;%PATH%"
cd /d "%~dp0..\packages\client"
node "..\..\node_modules\vite\bin\vite.js" %*
