@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==================================================================
echo   BlackEvidence 录像助手
echo ------------------------------------------------------------------
echo   这个窗口要一直开着，可以最小化。
echo   想退出：Ctrl+C，或者直接关掉这个窗口。
echo.
echo   第一次用先把 config.ini 里的 paths.wow_root
echo   写成你的魔兽世界游戏目录，例如：
echo       wow_root = D:\World of Warcraft\_retail_
echo ==================================================================
echo.
python blackevidence_recorder.py %*
echo.
echo 程序已退出（退出码 %ERRORLEVEL%）。日志见 recorder.log
echo.
pause
