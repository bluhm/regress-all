#!/bin/sh

set -eu

usage() {
	echo "$(basename $0): FROM TO" 1>&2
	echo "\tgenerate pngs of the gnuplot keys in a given range using" 1>&2
	echo "\timagemagick's convert. FROM and TO are positive integers" 1>&2
	exit 1
}

FROM="$1"
TO="$2"
which gnuplot > /dev/null && which convert > /dev/null || usage
if [ -z "$FROM" ] || [ -n "${FROM#[0-9]*}" ] || [ "$FROM" -le "0" ] ||\
    [ -z "$TO" ] || [ -n "${TO##[0-9]*}" ] || [ "$TO" -lt "$FROM" ]; then
	usage
fi

PLOT=$(mktemp)
cat > $PLOT << EOG
\$point << EOD
1
EOD
set xrange [0.99:1.01]
set yrange [0.99:1.01]
set terminal png transparent
do for [i = $FROM:$TO] {
	set output "key_".i.".png"
	plot \$point using 1:1 with points lc i pt i
}
EOG

gnuplot $PLOT >> /dev/null

for key in key_*.png; do
	convert $key -crop 16x24+339+218 $key
done
