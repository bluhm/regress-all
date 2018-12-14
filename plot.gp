#!/usr/local/bin/gnuplot

# Copyright (c) 2018 Moritz Buhl <mbuhl@genua.de>
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
# OUT_FILE	Path,	svg output file 
# TESTS		String,	testnames to filter and plot, space separated,
#			format: "test1 subtest1 test2 sub2 ... testN subN"
#
# The following variables are optional:
# CHECKOUT_DATE	UNIX time stamp, filter for a "checkout" value
# QUIRKS	String, format: "date1 descr1 date2 descr2 ... dateN descrN"
# RUN_DATE	UNIX time stamp, filter for a "run" value
# TITLE		String,	plot title
# UNIT		String, unit for the y-axis

if (!exists("DATA_FILE") || !exists("OUT_FILE") || !exists("TESTS")) {
    exit error "Please define DATA_FILE, OUT_FILE and TESTS."
    exit status 1
}

set border 3
set datafile separator whitespace
set key bmargin left vertical Right
set output OUT_FILE
if (exists("TITLE")) { set title TITLE }
if (exists("UNIT")) { set ylabel UNIT }
if (!exists("QUIRKS")) { QUIRKS = "" }

if (exists("CHECKOUT_DATE")) {
    if (exists("RUN_DATE")) {
	stats DATA_FILE using 4:(strcol(3) eq RUN_DATE?
	    (strcol(4) eq CHECKOUT_DATE? $6:NaN):NaN) nooutput
    } else {
	stats DATA_FILE using 4:(strcol(4) eq CHECKOUT_DATE? $6:NaN) nooutput
    }
} else {
    if (exists("RUN_DATE")) {
	stats DATA_FILE using 4:(strcol(3) eq RUN_DATE? $6:NaN) nooutput
    } else {
	stats DATA_FILE using 4:6 nooutput
    }
}

# adjust axes after this check to prevent warnings
if (!exists("STATS_records")) {
    set terminal svg
    set label "NO DATA" at 0.5,0.5
    set xrange[0:1]
    set yrange[0:1]
    plot 0
    exit
}

if (exists("CHECKOUT_DATE")) {
    set xrange[STATS_min_x : (STATS_max_x > STATS_min_x? STATS_max_x : "*")]
    set xlabel "Run #"
} else {
    set xrange[STATS_min_x : (STATS_max_x > STATS_min_x? STATS_max_x : "*")]
    set format x "%Y-%m-%d"
    set timefmt "%s"
    set xdata time
    set xlabel "Checkout (date)" offset 0,-1
    set xtics rotate by 45 offset -2,-2.5
}

points = (STATS_records / (words(TESTS) / 2)) + 1
set terminal svg size (30 * points), (480 + (words(TESTS) / 2) * 12) dynamic

# draw quirks
do for [IDX = 1:words(QUIRKS):2] {
    XPOS = word(QUIRKS, IDX)
    DESCR = word(QUIRKS, IDX+1)
    set arrow from XPOS/2, graph 0 to XPOS/2, graph 1 nohead
    set label DESCR at XPOS,STATS_max_y offset -(strlen(DESCR)/2),0
}


# draw test results
if (exists("CHECKOUT_DATE")) {
    if (exists("RUN_DATE")) {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(3) eq RUN_DATE? ( \
		strcol(4) eq CHECKOUT_DATE? ( \
		    strcol(1) eq word(TESTS,test)? ( \
			strcol(2) eq word(TESTS,test+1)? $6:NaN \
		    ):NaN \
		):NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1)
    } else {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(4) eq CHECKOUT_DATE? ( \
		strcol(1) eq word(TESTS,test)? ( \
		    strcol(2) eq word(TESTS,test+1)? $6:NaN \
		):NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1)
    }
} else {
    if (exists("RUN_DATE")) {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(3) eq RUN_DATE? ( \
		strcol(1) eq word(TESTS,test)? ( \
		    strcol(2) eq word(TESTS,test+1)? $6:NaN \
		):NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1)
    } else {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(1) eq word(TESTS,test)? ( \
		strcol(2) eq word(TESTS,test+1)? $6:NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1)
    }
}
