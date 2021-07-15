@echo off
fglcomp -M testutils
IF %errorlevel% NEQ 0 GOTO myend
fglform -M test
IF %errorlevel% NEQ 0 GOTO myend
fglcomp -M test
IF %errorlevel% NEQ 0 GOTO myend
fglcomp -M runtests
IF %errorlevel% NEQ 0 GOTO myend
fglrun runtests
:myend
