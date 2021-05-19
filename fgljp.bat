@echo off
set FGLJPDIR=%~dp0
set THISDRIVE=%~dd0
FOR %%i IN ("%CD%") DO (
  set MYDRIVE=%%~di
)
pushd %CD%
%THISDRIVE%
cd %FGLJPDIR%
rem compile mygetopt first as it is used b fgljp
set FGL_LENGTH_SEMANTICS=BYTE
set LANG=.fglutf8
fglcomp -M -r -Wall mygetopt.4gl
IF %errorlevel% NEQ 0 GOTO myend
fglcomp -M -r -Wall fgljp.4gl
IF %errorlevel% NEQ 0 GOTO myend
popd
%MYDRIVE%
fglrun %FGLJPDIR%\fgljp.42m %*
:myend
