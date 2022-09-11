#!/usr/local/bin/gnuplot

# Copyright (c) 2018-2019 Moritz Buhl <mbuhl@genua.de>
# Copyright (c) 2020 Alexander Bluhm <bluhm@genua.de>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# plot test results, the following variables are required:
# DATA_FILE	Path,	plot data file, space separated,
#			format: "test subtest run checkout repeat value unit"
# PREFIX	Path,	png output file
# TESTS		String,	testnames to filter and plot, space separated,
#			format: "test1 subtest1 test2 sub2 ... testN subN"
#
# The following variables are optional:
# QUIRKS	String, format: "date1 descr1 date2 descr2 ... dateN descrN"
# RUN_DATE	UNIX time stamp, filter for a "run" value
# TITLE		String,	plot title
# UNIT		String, unit for the y-axis

if (!exists("DATA_FILE") || !exists("PREFIX") || !exists("TESTS")) {
    exit error "Please define DATA_FILE, PREFIX and TESTS."
    exit status 1
}

set datafile separator whitespace

if (!exists("TITLE")) { TITLE = "" }
if (!exists("UNIT")) { UNIT = "" }
if (!exists("QUIRKS")) { QUIRKS = "" }
if (!exists("LATEX")) { LATEX = 0 }

if (exists("RUN_DATE")) {
    stats DATA_FILE using 4:(strcol(3) eq RUN_DATE? $6:NaN) nooutput
} else {
    stats DATA_FILE using 4:6 nooutput
}

# If there are not data points, create an empty image to prevent future gnuplot
# invocations. To prevent warnings, set most style settings after this check.
if (!exists("STATS_records")) {
    set terminal png size 240,80
    set title TITLE."\nNO DATA" offset first 0,0
    set yrange [-1:1]
    unset tics
    unset border
    plot 0 lc rgb 'white'
    exit
}

# work around min == max
if (!exists("XRANGE_MIN")) { XRANGE_MIN = STATS_min_x - 1 }
if (!exists("XRANGE_MAX")) { XRANGE_MAX = STATS_max_x + 1 }
if (!exists("YRANGE_MIN")) { YRANGE_MIN = 0 }
if (!exists("YRANGE_MAX")) { YRANGE_MAX = STATS_max_y + 1 }

set xrange[XRANGE_MIN : XRANGE_MAX]
set yrange[YRANGE_MIN : YRANGE_MAX]
set title TITLE
set ylabel UNIT
set format x "%Y-%m-%d"
set timefmt "%s"
set xdata time
set xlabel "Checkout (date)"
set tics out
set border 3
if (LATEX) {
    set output PREFIX.".tex"
    set terminal epslatex color size 10.5, 5
} else {
    set output PREFIX.".png"
    set terminal png transparent size 1360, 768
    set style textbox opaque noborder fillcolor rgb "white"
}
unset key

# draw quirks
lbl_index = 65
descr_suffix = ""
do for [i = 1:words(QUIRKS)] {
    XPOS = (0.0+int(word(QUIRKS, i))-XRANGE_MIN)/(XRANGE_MAX-XRANGE_MIN)
    if (XPOS > 0 && XPOS < 1) {
	DESCR = sprintf("%c%s", lbl_index, descr_suffix)
	set arrow from graph XPOS,0 to graph XPOS,1 nohead lw 1 lc rgb 'black'
	set label DESCR at graph XPOS, graph 1 noenhanced \
	    offset character -.5, character 0.7 front
    }
    if (lbl_index == 90) { # jump from Z to a
	lbl_index = lbl_index + 6
    }
    lbl_index = lbl_index + 1

    if (lbl_index == 123) { # jump from z to A'
	lbl_index = 65
	descr_suffix = descr_suffix . "'"
    }
}

# draw complete plot
if (exists("RUN_DATE")) {
    plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	strcol(3) eq RUN_DATE? ( \
	    strcol(1) eq word(TESTS,test)? ( \
		strcol(2) eq word(TESTS,test+1)? $6:NaN \
	    ):NaN \
	):NaN \
    ) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced ps 3
} else {
    plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	strcol(1) eq word(TESTS,test)? ( \
	    strcol(2) eq word(TESTS,test+1)? $6:NaN \
	):NaN \
    ) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced ps 3
}

if (LATEX) {
    exit
}

# draw frame
set output PREFIX."_0.png"
plot 0 notitle lc bgnd

# draw data
set title tc bgnd
set xtics tc bgnd
set ytics tc bgnd
set xlabel tc bgnd
set ylabel tc bgnd
set border lc bgnd
unset border
unset arrow
unset label

do for [test = 1:words(TESTS):2] {
    i = test/2+1
    set output PREFIX."_".i.".png"
    if (exists("RUN_DATE")) {
	plot DATA_FILE using 4:( \
	    strcol(3) eq RUN_DATE? ( \
		strcol(1) eq word(TESTS,test)? ( \
		    strcol(2) eq word(TESTS,test+1)? $6:NaN \
		):NaN \
	    ):NaN \
	) with points lc i pt i
    } else {
	plot DATA_FILE using 4:( \
	    strcol(1) eq word(TESTS,test)? ( \
		strcol(2) eq word(TESTS,test+1)? $6:NaN \
	    ):NaN \
	) with points lc i pt i
    }
}
