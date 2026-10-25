@echo off
setlocal
REM MEGA65 Python build: generate tables, assemble with 64tass, write the D81 with c1541.
REM The first file on the disk is AUTOBOOT.C65, a one-line BASIC program (10 RUN"MEGA-PYTHON")
REM that a MEGA65 runs when it boots with the disk mounted (Xemu -autoload runs the first
REM file). Then the interpreter mega-python, mpy-ovl (the rest of the interpreter), and
REM the example and test programs as .py files.
set PROJECT=mega-python
if not exist target mkdir target
REM c1541 writes its settings under the user profile: keep them inside target\
if not exist target\userprofile\AppData\Roaming mkdir target\userprofile\AppData\Roaming
set "USERPROFILE=%CD%\target\userprofile"
set "APPDATA=%USERPROFILE%\AppData\Roaming"

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\%PROJECT%.prg 2>nul

python tools\gen_tables.py
if errorlevel 1 exit /b 1
python tools\mkpy.py
if errorlevel 1 exit /b 1
python tools\mkboot.py
if errorlevel 1 exit /b 1

.\64tass.exe --nostart -C -I src -D PASS=1 src\main.asm -l target\%PROJECT%.lbl -L target\%PROJECT%.lst -o target\image.bin
if errorlevel 1 exit /b 1
.\64tass.exe --nostart -C -I src -D PASS=2 src\main.asm -o target\image2.bin
if errorlevel 1 exit /b 1
python tools\split.py
if errorlevel 1 exit /b 1

cd target
..\c1541.exe -format "%PROJECT%,01" d81 %PROJECT%.d81 >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write autoboot.c65 autoboot.c65 >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write %PROJECT%.prg %PROJECT% >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write mpy-ovl mpy-ovl >nul
if errorlevel 1 (cd .. & exit /b 1)
for %%f in (py\*.py) do ..\c1541.exe -attach %PROJECT%.d81 -write py\%%~nxf %%~nxf >nul
cd ..

echo Built target\%PROJECT%.d81
