#GNU and nmake compatible
.SUFFIXES: .4gl .42m .per .42f

.4gl.42m:
	fglcomp -M -r -W all $<

.per.42f:
	fglform -M $<


all: fgljp.42m mygetopt.42m runonserver.42m getgdcpath.42m fgljpssh.42m

demo: fgljp.42m demo.42m demo.42f
	./fgljp demo.42m a b

demogmi: fgljp.42m demo.42m demo.42f
	./fgljp -r demo.42m a b

demogdc: fgljp.42m demo.42m demo.42f
	GDC=1 ./fgljp -v -g demo.42m a b

format:
	rm -f *.4gl~
	fglcomp -M --format --fo-inplace mygetopt.4gl
	fglcomp -M --format --fo-inplace fgljp.4gl
	fglcomp -M --format --fo-inplace demo.4gl

clean_prog:
	rm -f fgljp.42m mygetopt.42m

clean: clean_prog
	rm -f *.42? *.4gl~
	rm -rf priv cacheFT

dist: all 
