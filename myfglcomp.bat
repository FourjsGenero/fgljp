@echo off
setlocal EnableExtensions EnableDelayedExpansion
SETLOCAL
rem implement a kinda make for a particular 4gl file
set src=%1.4gl
set m42=%1.42m
set compile=0
set foo=0

IF NOT exist "%m42%" (
  rem echo not exist %m42%
  set compile=1
  set reason=%m42% does not exist
  ) else (
    goto :checknewest
  )
goto :end

:checknewest
FOR /F %%i IN ('DIR /B /OD %src% %m42%') DO set newest=%%i
rem echo newest:%newest%
IF "%newest%" == "%src%" (
    rem echo %src% is newer
    set compile=1
    set reason=%src% is newer
  ) else (
    rem echo %m42% is newer
    goto :checkpcode
  )
goto :end

:checkpcode
fglrun -r %m42%  > NUL 2>&1
if %errorlevel% NEQ 0 (
  rem echo reassemble of %m42% failed
  set compile=1
  set reason=%m42% is not valid pcode
)

:end
if %compile% EQU 1 (
  echo compile %src%, %reason%
  fglcomp -M -r -Wall %src%
) else (
  echo %m42% is up to date.
)
