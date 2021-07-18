@echo off
rem demonstrates fgljp in file transfer mode
del /F /Q demoft.txt
start fgljp --startfile demoft.txt -X
cd test
fglcomp -M testutils
IF %errorlevel% NEQ 0 GOTO myend
fglcomp -M wait_for_fgljp_start
IF %errorlevel% NEQ 0 GOTO myend
rem wait for fgljp to come up
fglrun wait_for_fgljp_start ../demoft.txt
IF %errorlevel% NEQ 0 GOTO myend
cd ..
fglcomp -M demo
IF %errorlevel% NEQ 0 GOTO myend
fglform -M demo
IF %errorlevel% NEQ 0 GOTO myend
fglrun demo
del /F /Q demoft.txt
:myend
