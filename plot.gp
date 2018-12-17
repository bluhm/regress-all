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

set datafile separator whitespace
set key bmargin left vertical Right
set output OUT_FILE

if (!exists("TITLE")) { TITLE = "" }
if (!exists("UNIT")) { UNIT = "" }
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

# If there are not data points, create an empty image to prevent future gnuplot
# invocations. To prevent warnings, set most style settings after this check.
if (!exists("STATS_records")) {
    set terminal svg size 120,80
    set title TITLE."\nNO DATA" offset first 0,0
    set yrange [-1:1]
    unset tics
    unset key
    unset border
    plot 0 lc rgb 'white'
    exit
}

set title TITLE
set ylabel UNIT
set xrange[STATS_min_x - 1 : STATS_max_x + 1] # work around min == max
set yrange[0 : *]

if (exists("CHECKOUT_DATE")) {
    set xlabel "Run #"
} else {
    set format x "%Y-%m-%d"
    set timefmt "%s"
    set xdata time
    set xlabel "Checkout (date)" offset 0,-1
    set xtics rotate by 45 offset -2,-2.5
}

points = (STATS_records / (words(TESTS) / 2)) + 1
# XXX Scaled image is unreadable small, disable for now.
#set terminal svg size (120 + 30 * points), (600 + (words(TESTS) / 2) * 20)
#set tmargin 120
set terminal svg

# draw quirks
set style textbox opaque noborder fillcolor rgb "white"
lbl_index = 1
do for [i = 1:words(QUIRKS)] {
    XPOS = (int(word(QUIRKS, i))-STATS_min_x)/(STATS_max_x-STATS_min_x)
    if (XPOS > 0 && XPOS < 1) {
	DESCR = sprintf("%d", lbl_index)
	lbl_index = lbl_index + 1
	set arrow from graph XPOS,0 to graph XPOS,1 nohead lw 1 lc rgb 'black'
	set label DESCR at graph XPOS, screen .9 noenhanced front boxed
    }
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
	) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced
    } else {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(4) eq CHECKOUT_DATE? ( \
		strcol(1) eq word(TESTS,test)? ( \
		    strcol(2) eq word(TESTS,test+1)? $6:NaN \
		):NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced
    }
} else {
    if (exists("RUN_DATE")) {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(3) eq RUN_DATE? ( \
		strcol(1) eq word(TESTS,test)? ( \
		    strcol(2) eq word(TESTS,test+1)? $6:NaN \
		):NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced
    } else {
	plot for [test = 1:words(TESTS):2] DATA_FILE using 4:( \
	    strcol(1) eq word(TESTS,test)? ( \
		strcol(2) eq word(TESTS,test+1)? $6:NaN \
	    ):NaN \
	) title word(TESTS,test)." ".word(TESTS,test+1) noenhanced
    }
}
