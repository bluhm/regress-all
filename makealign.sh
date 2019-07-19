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

{
	# create template
	for obj in $OBJS;
	do
		echo "\t\t. = ALIGN($PAGE_SIZE);"
		echo "\t\t${obj}ALIGNSECTION"
	done
	echo OBJECTS
	cat $LDSCRIPT
} |
sed "$(cat <<EOS
1,/^OBJECTS\$/{
    H
    d
}
/^[	 ]*\*(\..*) *\$/G
EOS)" |
sed "$(cat <<EOS
/^[	 ]*\*(\..*) *\$/,/^OBJECTS$/{
    /^[	 ]*\*(\..*) *\$/{
	s/.*\*\((\..*)\).*/\1/
	h
	d
    }
    /ALIGNSECTION/G
    s/ALIGNSECTION\n//
    /^OBJECTS$/d
}
EOS)"
