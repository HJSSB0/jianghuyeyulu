@echo off
rem 《江湖夜雨录》云存档服务器一键启动（需 Node.js >= 18）
rem 用法：双击本文件；或命令行 start_server.bat [端口]（默认 8787）
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo [错误] 未找到 node，请先安装 Node.js：https://nodejs.org
  pause
  exit /b 1
)
node save_server.mjs %1
pause
