#GNU and nmake compatible
.SUFFIXES: .4gl .42m

.4gl.42m:
	fglcomp -M -r -W all $<


all: fgljp.42m mygetopt.42m runonserver.42m

demo: fgljp.42m demo.42m
	./fgljp demo.42m a b

clean_prog:
	rm -f fgljp.42m mygetopt.42m

clean: clean_prog
	rm -f *.42?

dist: all 
