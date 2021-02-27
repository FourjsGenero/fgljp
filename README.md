# fgljp
Genero GAS like proxy to run GBC programs
fgl (j)ava (p)roxy 
Uses loads of IMPORT JAVA 

# Motivation

If you search an easy command line tool to run GBC in your desktop browser (and later on remote)
then fgljp is the right tool for you.

It is (almost) as easy as 
```
$ fglrun prog arg1 arg2
```
, just call your program with

```
$ fgljp prog arg1 arg2
```

Prerequisites:
FGL >= 3.10
JAVA >= 8


# How it works

1. fgljp starts the given program and sets up an http server as well as a socket server for the fglrun GUI output (both listening on the same port: fgljp auto senses the protocol).
2. It opens your default browser pointing to the suitable URL: voila, you should see the app, and DISPLAY statements appear on stdout like via GDC.

# Installation

You don't necessarily need to install fgljp.
If you did check out this repository you can call
```
$ <path_to_this_repository>/fgljp <yourprogram> ?arg? ?arg?
```
and it uses the fglcomp/fglrun in your PATH to compile and run fgljp.
Of course you can add also <path_to_this_repository> in your PATH .
