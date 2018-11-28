TEST = "time\_\-lp\_make\_\-CGENERIC.MP\_\-j8\_\-s"
TESTNAME = "time -lp make -CGENERIC.MP -j8 -s"
SUBTEST1 = "real"
SUBTEST2 = "user"
SUBTEST3 = "sys"

set title TESTNAME
set datafile separator whitespace
set terminal svg
set output OUT_FILE

MAX_Y = 0
# in case the test doesn't exist for a run:
STATS_min_y = 0
STATS_max_y = 1
STATS_min_x = 0
STATS_max_x = 1

stats DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST3? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)

set ylabel "Seconds (s)"
set yrange [0 : MAX_Y]

stats DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		$6 \
		: NaN \
	) \
	:NaN \
) nooutput
set xrange[STATS_min_x : (STATS_max_x > STATS_min_x? STATS_max_x : "*")]
set xlabel "Checkout (date)"
set timefmt "%s"
set xdata time # after stats
set format x "%Y-%m-%d"

plot \
DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) t SUBTEST1 with points lc 1 pointtype 1 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) t SUBTEST2 lc 2 pointtype 2 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq TEST? \
	(strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST3? \
			$6 \
			:NaN \
		) \
		:NaN \
	) \
	: NaN \
) t SUBTEST3 lc 3 pointtype 3 ps 0.25

#pause -1
