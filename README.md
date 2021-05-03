# fgljp
Genero GAS like proxy to run GBC programs from the command line
fgl (j)ava (p)roxy 
Uses loads of IMPORT JAVA 

# Motivation

If you search an easy command line tool to run GBC in your desktop browser
then fgljp is the right tool for you.

It is (almost) as easy as 
```
$ fglrun prog arg1 arg2
```
, just call your program with

```
$ fgljp prog arg1 arg2
```
If you start fgljp with a Genero program argument fgljp emulates a GAS running on the client side.
This assumes that the fglrun to work with runs also locally at the client side.


Starting fgljp without a program argument turns fgljp into a GDC equivalent:
It then listens on 6400 for incoming connections and opens the browser with
GBC.
GBC shows the Genero program caused by a local or remote invocation of fglrun.

```
$ ./fgljp &
{"port":6400,"FGLSERVER":"localhost:0","pid":18092}
[1] 18120
$ fglcomp demo && fglrun demo
```

This is the remote mode. There is also no GAS needed to let the remote mode work.
In comparison with GDC the difference is that no (potentially dangerous) GDC frontcalls are possible (yet) which makes fgljp a very safe replacement to develop GBC programs intended to run in the browser.
There is literally no difference vs a GBC using GAS on a remote server.
Obviously you need an fglrun on the *client* side to make fgljp working, but there is no database needed.

Prerequisites:
FGL >= 3.10
JAVA >= 8


# How it works

1. fgljp starts the given program and sets up an http server as well as a socket server for the fglrun GUI output (both listening on the same port: fgljp auto senses the protocol).
2. It opens your default browser pointing to the suitable URL: voila, you should see the app, and DISPLAY statements appear on stdout like via GDC.
3. In remote mode (start without program arguments) it listens for incoming connections. As soon as a fglrun process connects it does the same as GDC in UR mode: downloading the GBC and providing a http URL for GBC to work with.
The difference is: it uses your system browser.
Under the hood fgljp implements the encapsulated protocol using filetransfer in order to achive that,
it emulates hence a GDC.

# Installation

You don't necessarily need to install fgljp.
If you did check out this repository you can call
```
$ <path_to_this_repository>/fgljp ?yourprogram? ?arg? ?arg?
```

Windows
```
C:> <path_to_this_repository>\fgljp ?yourprogram? ?arg? ?arg?
```

and it uses the fglcomp/fglrun in your PATH to compile and run fgljp.
Of course you can add also <path_to_this_repository> in your PATH .
