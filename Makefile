#GNU and nmake compatible
.SUFFIXES: .4gl .42m .per .42f

.4gl.42m:
	fglcomp -M -r -W all $<

.per.42f:
	fglform -M $<


all: fgljp.42m mygetopt.42m runonserver.42m

demo: fgljp.42m demo.42m demo.42f
	./fgljp demo.42m a b

demogmi: fgljp.42m demo.42m demo.42f
	./fgljp -r demo.42m a b

clean_prog:
	rm -f fgljp.42m mygetopt.42m

clean: clean_prog
	rm -f *.42?

dist: all 
