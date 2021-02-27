@echo off
set FGLJPDIR=%~dp0
set THISDRIVE=%~dd0
FOR %%i IN ("%CD%") DO (
  set MYDRIVE=%%~di
)
pushd %CD%
%THISDRIVE%
cd %FGLJPDIR%
fglcomp -M -r -Wall fgljp.4gl
fglcomp -M -r -Wall mygetopt.4gl
IF %errorlevel% NEQ 0 GOTO myend
popd
%MYDRIVE%
fglrun %FGLJPDIR%\fgljp.42m %*
:myend
