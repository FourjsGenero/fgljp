#include <windows.h>

/*
Passs a command line 'as is' but hide the console window
*/
int APIENTRY WinMain(
  HINSTANCE hInstance,
  HINSTANCE hPrevInstance,
  LPSTR cmdline,
  int nCmdShow)
{
  STARTUPINFO si;
  ZeroMemory(&si, sizeof(STARTUPINFO));
  si.cb = sizeof(STARTUPINFO);
  nCmdShow = 0;
  hPrevInstance = 0;
  
  PROCESS_INFORMATION pi;
  ZeroMemory(&pi, sizeof(PROCESS_INFORMATION));
  
  int code = -1;
  if (CreateProcess(
    NULL, // means first argument of the command line is the executable
    cmdline,
    NULL,
    NULL,
    FALSE, // Deny inherited handles
    CREATE_NO_WINDOW, // Hide the console
    NULL,  // inherit env
    NULL,  // inherit pwd
    &si,
    &pi))
  {
    // Wait infinite
    DWORD err = WaitForSingleObject(pi.hProcess, INFINITE);
    if (err != WAIT_OBJECT_0)
    {
      TerminateProcess(pi.hProcess, 0);
    }
    else
    {
      DWORD err2;
      if (GetExitCodeProcess(pi.hProcess, &err2))
      {
        code = err2;
      }
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
  }
  
  return code;
}
