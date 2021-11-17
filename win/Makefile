all: whide.exe

whide.exe:whide.c
	cl /W4 /SUBSYSTEM:windows whide.c
	del /Q /F whide.obj

clean:
	del /Q /F *.obj *.exe *.un~

