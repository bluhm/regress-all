TEST = "TCP Performance"
SUBTEST1 = "iperf3_-c10.3.0.33_-w1m_-t60"
SUBTEST1SUB1 = "sender"
SUBTEST1SUB2 = "receiver"
SUBTEST2 = "iperf3_-c10.3.0.33_-w1m_-t60_-R"
SUBTEST2SUB1 = "sender"
SUBTEST2SUB2 = "receiver"
SUBTEST3 = "tcpbench_-S1000000_-t60_-n100_10.3.0.33"
SUBTEST3SUB1 = "sender"
SUBTEST4 = "tcpbench_-S1000000_-t60_10.3.0.33"
SUBTEST4SUB1 = "sender"

set title TEST
set datafile separator whitespace
set terminal svg
set output OUT_FILE



MAX_Y = 0
# in case the test doesn't exist for a run:
STATS_min_y = 0
STATS_max_y = 1
STATS_min_x = 0
STATS_max_x = 1
stats DATA_FILE using 4:(strcol(1) eq SUBTEST1? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1SUB1? \
			$6 \
			:NaN \
		) \
		: NaN \
	) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq SUBTEST1? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1SUB2? \
			$6 \
			:NaN \
		) \
		: NaN \
	) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq SUBTEST2? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2SUB1? \
			$6 \
			:NaN \
		) \
		: NaN \
	) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq SUBTEST2? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2SUB2? \
			$6 \
			:NaN \
		) \
		: NaN \
	) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq SUBTEST3? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST3SUB1? \
			$6 \
			:NaN \
		) \
		: NaN \
	) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)
stats DATA_FILE using 4:(strcol(1) eq SUBTEST4? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST4SUB1? \
                $6 \
                :NaN \
        ) \
                :NaN \
        ) \
        : NaN \
) nooutput
MAX_Y = (MAX_Y < STATS_max_y? STATS_max_y : MAX_Y)

set ylabel "bits/sec"
set yrange [0 : MAX_Y]

set xrange[STATS_min_x : (STATS_max_x > STATS_min_x? STATS_max_x : "*")]
set xlabel "Checkout (date)"
set timefmt "%s"
set xdata time # after stats
set format x "%Y-%m-%d"

plot \
DATA_FILE using 4:(strcol(1) eq SUBTEST1? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1SUB1? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST1.' '.SUBTEST1SUB2 with points lc 1 pointtype 1 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq SUBTEST1? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST1SUB2? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST1.' '.SUBTEST1SUB2 lc 2 pointtype 2 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq SUBTEST2? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2SUB1? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST2.' '.SUBTEST2SUB1 lc 3 pointtype 3 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq SUBTEST2? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST2SUB2? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST2.' '.SUBTEST2SUB2 lc 4 pointtype 4 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq SUBTEST3? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST3SUB1? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST3.' '.SUBTEST3SUB1 lc 5 pointtype 5 ps 0.25, \
DATA_FILE using 4:(strcol(1) eq SUBTEST4? \
        (strcol(3) eq RUN_DATE? \
		(strcol(2) eq SUBTEST4SUB1? \
			$6 \
			:NaN \
		) \
                :NaN \
        ) \
        : NaN \
) t SUBTEST4.' '.SUBTEST4SUB1 lc 6 pointtype 6 ps 0.25

#pause -1
