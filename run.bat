@echo off
call build.bat
if errorlevel 1 exit /b 1

C:\Emulation\Mega65\xmega65.exe -8 "%~dp0target\mega-python.d81" -autoload
