#!/bin/sh -
# adapt kernel linker script to align all objects to page size

if [[ $# -lt 8 ]]; then
	echo usage: makealign.sh ld.script \
	    locore0.o gap.o ... param.o ioconf.o vers.o swapgeneric.o 1>&2
	exit 2
fi

LDSCRIPT=$1
shift
OBJS="$@"

PAGE_SIZE=$(sysctl -n hw.pagesize)

# create template
for f in $OBJS;
do
	TEMPLATE=$(cat <<- EOF
	$TEMPLATE
	. = ALIGN($PAGE_SIZE);
	$f(SECTION);
EOF)
done

while read l;
do
	SECTION=$(echo "$l" | grep -o '\s*\*(\(.*\))$')
	if [ $? -eq 0 ]; then
		echo "$TEMPLATE" | \
		    sed "s/SECTION/$(echo $SECTION| cut -c 2- | tr -d '()')/"
	else
		echo "$l"
	fi
done <$LDSCRIPT
