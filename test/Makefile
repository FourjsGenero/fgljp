#GNU and nmake compatible
.SUFFIXES: .4gl .42m .per .42f

.4gl.42m:
	fglcomp -M -r -W all $<

.per.42f:
	fglform -M $<


all: test.42m test.42f testutils.42m runtests.42m

test: all
	-killall fglrun
	fglrun runtests

clean: 
	rm -f *.42? *.4gl~ *.log 'logo?.png' tt
	rm -rf priv cacheFT

