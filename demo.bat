@echo off
rem demonstrates the GAS mode
fglcomp -M demo
IF %errorlevel% NEQ 0 GOTO myend
fglform -M demo
IF %errorlevel% NEQ 0 GOTO myend
fgljp demo
:myend
echo myend %1
