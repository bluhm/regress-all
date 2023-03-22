LISTS =		$(wildcard *.list)
PLS =		$(wildcard *.pl)
PMS =		$(wildcard *.pm)
SHS =		$(wildcard *.sh)
SORTED =	$(LISTS:.list=.sorted)
SYNTAX =	$(PMS:.pm=.syntax) $(PLS:.pl=.syntax) $(SHS:.sh=.syntax)

.PHONY: all copyyear sorted syntax clean

all: syntax sorted copyyear

sorted: ${SORTED}

%.sorted: %.list
	@sort -uc $<
	@echo $< sorted unique
	@date >$@

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

copyyear: LICENSE
	@grep -e "Copyright .*`date +%Y` " LICENSE

clean:
	rm -f -- *.sorted *.syntax
