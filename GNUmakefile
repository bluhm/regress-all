PLS =		$(wildcard *.pl)
PMS =		$(wildcard *.pm)
SHS =		$(wildcard *.sh)
SYNTAX =	$(PMS:.pm=.syntax) $(PLS:.pl=.syntax) $(SHS:.sh=.syntax)

all: syntax

syntax: ${SYNTAX}

%.syntax: %.pl
	@perl -c `sed -n '1s/^#!.* -T.*/-T/p;q' $<` $<
	@date >$@

%.syntax: %.pm
	@perl -I. -c $<
	@date >$@

%.syntax: %.sh
	@sh -n $<
	@echo $< syntax OK
	@date >$@

clean:
	rm -f -- *.syntax
