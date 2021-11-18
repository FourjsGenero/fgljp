#GNU and nmake compatible
.SUFFIXES: .4gl .42m .per .42f

.4gl.42m:
	fglcomp -M -r -W all $<

.per.42f:
	fglform -M $<


all: fgljp.42m mygetopt.42m runonserver.42m getgdcpath.42m fglssh.42m

demo: fgljp.42m demo.42m demo.42f
#	./fgljp -v demo.42m a b
	./fgljp demo.42m a b

test/wait_for_fgljp_start.42m:
	make -C test

#starts the demo in file transfer mode in one rush
demoft: fgljp.42m demo.42m demo.42f test/wait_for_fgljp_start.42m
	rm -f demoft.txt
	./fgljp --startfile demoft.txt -X &
	cd test&&fglrun wait_for_fgljp_start ../demoft.txt&&cd ..
	fglrun demo.42m a b

rundemo: demo.42m demo.42f
	fglrun demo.42m a b

demogmi: fgljp.42m demo.42m demo.42f
	./fgljp -r demo.42m a b

demogdc: fgljp.42m demo.42m demo.42f
	GDC=1 ./fgljp -v -g demo.42m a b

format:
	rm -f *.4gl~
	fglcomp -M --format --fo-inplace mygetopt.4gl
	fglcomp -M --format --fo-inplace fgljp.4gl
	fglcomp -M --format --fo-inplace fglssh.4gl
	fglcomp -M --format --fo-inplace demo.4gl

clean_prog:
	rm -f fgljp.42m mygetopt.42m

clean: clean_prog
	rm -f *.42? *.4gl~
	rm -rf priv cacheFT

dist: all 
