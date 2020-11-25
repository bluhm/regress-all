#!/usr/bin/perl
# module with global variables for perform tests

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2018-2019 Moritz Buhl <mbuhl@genua.de>
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

use strict;
use warnings;

package Testvars;
use Exporter 'import';
our @EXPORT_OK = qw(@PLOTORDER %TESTPLOT %TESTORDER %TESTDESC);

########################################################################

our @PLOTORDER;
@PLOTORDER = qw(tcp tcp6 udp udp6 linux linux6 forward forward6 make fs);

our %TESTPLOT;
my @testplot = (
    'iperf3_-c10.3.0.33_-w1m_-t10'					=> "tcp",
    'iperf3_-c10.3.2.35_-w1m_-t10'					=> "tcp",
    'iperf3_-c10.3.45.35_-w1m_-t10'					=> "tcp",
    'iperf3_-c10.3.0.33_-w1m_-t10_-R'					=> "tcp",
    'iperf3_-c10.3.2.35_-w1m_-t10_-R'					=> "tcp",
    'iperf3_-c10.3.45.35_-w1m_-t10_-R'					=> "tcp",
    'tcpbench_-S1000000_-t10_10.3.0.33'					=> "tcp",
    'tcpbench_-S1000000_-t10_10.3.2.35'					=> "tcp",
    'tcpbench_-S1000000_-t10_10.3.45.35'				=> "tcp",
    'tcpbench_-S1000000_-t10_-n100_10.3.0.33'				=> "tcp",
    'tcpbench_-S1000000_-t10_-n100_10.3.2.35'				=> "tcp",
    'tcpbench_-S1000000_-t10_-n100_10.3.45.35'				=> "tcp",
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10'				=> "udp",
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10'				=> "udp",
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10'				=> "udp",
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R'				=> "udp",
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R'				=> "udp",
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10_-R'				=> "udp",
    'udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33'			=> "udp",
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35'			=> "udp",
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.45.35'			=> "udp",
    'udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32'			=> "udp",
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34'			=> "udp",
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.45.34'			=> "udp",
    'udpbench_-l36_-t10_-r_ot13_send_10.3.0.33'				=> "udp",
    'udpbench_-l36_-t10_-r_ot15_send_10.3.2.35'				=> "udp",
    'udpbench_-l36_-t10_-r_ot15_send_10.3.45.35'			=> "udp",
    'udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32'				=> "udp",
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34'				=> "udp",
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.45.34'			=> "udp",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10'			=> "tcp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10'			=> "tcp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10_-R'			=> "tcp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10_-R'			=> "tcp6",
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0302::35'			=> "tcp6",
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0345::35'			=> "tcp6",
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0302::35'		=> "tcp6",
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0345::35'		=> "tcp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10'		=> "udp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10'		=> "udp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10_-R'		=> "udp6",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10_-R'		=> "udp6",
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "udp6",
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> "udp6",
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "udp6",
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> "udp6",
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "udp6",
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> "udp6",
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "udp6",
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> "udp6",
    'iperf3_-c10.3.3.36_-w2m_-t10'					=> "linux",
    'iperf3_-c10.3.46.36_-w2m_-t10'					=> "linux",
    'iperf3_-c10.3.3.36_-w2m_-t10_-R'					=> "linux",
    'iperf3_-c10.3.46.36_-w2m_-t10_-R'					=> "linux",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10'			=> "linux6",
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10'			=> "linux6",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10_-R'			=> "linux6",
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10_-R'			=> "linux6",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10'			=> "forward",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10_-R'			=> "forward",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-t10'				=> "forward",
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10'			=> "forward",
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10_-R'			=> "forward",
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10'			=> "forward",
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10_-R'			=> "forward",
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10'			=> "forward",
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10_-R'			=> "forward",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10'	=> "forward6",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10_-R'	=> "forward6",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-t10'		=> "forward6",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10'	=> "forward6",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10_-R'	=> "forward6",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10'	=> "forward6",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10_-R'	=> "forward6",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10'	=> "forward6",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10_-R'	=> "forward6",
    'time_-lp_make_-CGENERIC.MP_-j4_-s'					=> "make",
    'time_-lp_make_-CGENERIC.MP_-j8_-s'					=> "make",
    'time_-lp_fs_mark_-dfs_mark_-D8_-N16_-n256_-t8'			=> "fs",
);

%TESTPLOT = @testplot;
if (2 * keys %TESTPLOT != @testplot) {
    die "testplot keys not unique";
}
my %plots;
@plots{@PLOTORDER} = ();
while (my ($k, $v) = each %TESTPLOT) {
    die "invalid plot $v for test $k" unless exists $plots{$v};
}

########################################################################

our %TESTORDER;
# explain most significant to least significant digits
# - 0xxxxx type
#   1xxxxx network ot12/ot13
#   2xxxxx network ot14/ot15
#   3xxxxx network ot14/lt16
#   4xxxxx network ot14/ot15 45
#   5xxxxx network ot14/lt16 46
#   6xxxxx network lt13/ot14/lt16 36 34 46 56
#   8xxxxx make kernel
#   9xxxxx file system
# - x0xxxx family
#   x1xxxx network IPv4
#   x2xxxx network IPv6
# - xx0xxx subsystem
#   xx1xxx network stack
#   xx2xxx network forward
#   xx3xxx network relay splice
#   xx4xxx network relay splice and remote stack
#   xx5xxx network relay splice and local stack
# - xxx0xx protocol
#   xxx1xx iperf tcp
#   xxx2xx tcpbench
#   xxx3xx iperf udp
#   xxx4xx iperf udp 10Gbit
#   xxx5xx udpbench
# - xxxx0x aspects
#   xxxx1x iperf forward direction
#   xxxx2x iperf reverse direction
#   xxxx1x tcpbench single connction
#   xxxx2x tcpbench 100 connections
#   xxxx1x udpbench send large packets
#   xxxx2x udpbench receive large packets
#   xxxx3x udpbench send small packets
#   xxxx4x udpbench receive small packets
#   xxxx5x iperf forward direction 10 connections
#   xxxx6x iperf reverse direction 10 connections
#   xxxx4x 4 make processes
#   xxxx8x 8 make processes
#   xxxx8x 8 fs_mark threads
# - xxxxx0 tune
#   xxxxx1 10 secondes timeout
#   xxxxx2 60 secondes timeout
#   xxxxx2 udpbench wrong packet length
#   xxxxx3 iperf udp bandwidth 10G
#   xxxxx3 iperf tcp window 1m
#   xxxxx4 iperf tcp window 2m
#   xxxxx5 iperf tcp window 400k
#   xxxxx6 iperf tcp window 410k
my @testorder = (
    'iperf3_-c10.3.0.33_-w1m_-t10'					=> 111111,
    'iperf3_-c10.3.2.35_-w1m_-t10'					=> 211111,
    'iperf3_-c10.3.45.35_-w1m_-t10'					=> 411111,
    'iperf3_-c10.3.0.33_-w1m_-t60'					=> 111112,
    'iperf3_-c10.3.0.33_-w1m_-t10_-R'					=> 111121,
    'iperf3_-c10.3.2.35_-w1m_-t10_-R'					=> 211121,
    'iperf3_-c10.3.45.35_-w1m_-t10_-R'					=> 411121,
    'iperf3_-c10.3.0.33_-w1m_-t60_-R'					=> 111122,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10'			=> 121111,
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10'			=> 221111,
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10'			=> 421111,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60'			=> 121112,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10_-R'			=> 121121,
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10_-R'			=> 221121,
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10_-R'			=> 421121,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60_-R'			=> 121122,
    'iperf3_-c10.3.3.36_-t10'						=> 311111,
    'iperf3_-c10.3.46.36_-t10'						=> 511111,
    'iperf3_-c10.3.3.36_-t60'						=> 311112,
    'iperf3_-c10.3.3.36_-w1m_-t10'					=> 311113,
    'iperf3_-c10.3.3.36_-w2m_-t10'					=> 311114,
    'iperf3_-c10.3.46.36_-w2m_-t10'					=> 511114,
    'iperf3_-c10.3.3.36_-w400k_-t10'					=> 311115,
    'iperf3_-c10.3.3.36_-w410k_-t10'					=> 311116,
    'iperf3_-c10.3.3.36_-t10_-R'					=> 311121,
    'iperf3_-c10.3.46.36_-t10_-R'					=> 511121,
    'iperf3_-c10.3.3.36_-t60_-R'					=> 311122,
    'iperf3_-c10.3.3.36_-w1m_-t10_-R'					=> 311123,
    'iperf3_-c10.3.3.36_-w2m_-t10_-R'					=> 311124,
    'iperf3_-c10.3.46.36_-w2m_-t10_-R'					=> 511124,
    'iperf3_-c10.3.3.36_-w400k_-t10_-R'					=> 311125,
    'iperf3_-c10.3.3.36_-w410k_-t10_-R'					=> 311126,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10'				=> 321111,
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-t10'				=> 521111,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60'				=> 321112,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10'			=> 321113,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10'			=> 321114,
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10'			=> 521114,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10'			=> 321115,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10'			=> 321116,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10_-R'			=> 321121,
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-t10_-R'			=> 521121,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60_-R'			=> 321122,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10_-R'			=> 321123,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10_-R'			=> 321124,
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10_-R'			=> 521124,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10_-R'			=> 321125,
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10_-R'			=> 321126,
    'tcpbench_-S1000000_-t10_10.3.0.33'					=> 111211,
    'tcpbench_-S1000000_-t10_10.3.2.35'					=> 211211,
    'tcpbench_-S1000000_-t10_10.3.45.35'				=> 411211,
    'tcpbench_-S1000000_-t60_10.3.0.33'					=> 111212,
    'tcpbench_-S1000000_-t10_-n100_10.3.0.33'				=> 111221,
    'tcpbench_-S1000000_-t10_-n100_10.3.2.35'				=> 211221,
    'tcpbench_-S1000000_-t10_-n100_10.3.45.35'				=> 411221,
    'tcpbench_-S1000000_-t60_-n100_10.3.0.33'				=> 111222,
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0300::33'			=> 121211,
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0302::35'			=> 221211,
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0345::35'			=> 421211,
    'tcpbench_-S1000000_-t60_fdd7:e83e:66bc:0300::33'			=> 121212,
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0300::33'		=> 121221,
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0302::35'		=> 221221,
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0345::35'		=> 421221,
    'tcpbench_-S1000000_-t60_-n100_fdd7:e83e:66bc:0300::33'		=> 121222,
    'iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10'				=> 111311,
    'iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10'				=> 211311,
    'iperf3_-c10.3.45.35_-u_-b0_-w1m_-t10'				=> 411311,
    'iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10_-R'				=> 111321,
    'iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10_-R'				=> 211321,
    'iperf3_-c10.3.45.35_-u_-b0_-w1m_-t10_-R'				=> 411321,
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10'				=> 111413,
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10'				=> 211413,
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10'				=> 411413,
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R'				=> 111423,
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R'				=> 211423,
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10_-R'				=> 411423,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10'		=> 121413,
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10'		=> 221413,
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10'		=> 421413,
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10_-R'		=> 121423,
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10_-R'		=> 221423,
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10_-R'		=> 421423,
    'udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33'			=> 111511,
    'udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32'			=> 111521,
    'udpbench_-l36_-t10_-r_ot13_send_10.3.0.33'				=> 111531,
    'udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32'				=> 111541,
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35'			=> 211511,
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.45.35'			=> 411511,
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34'			=> 211521,
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.45.34'			=> 411521,
    'udpbench_-l36_-t10_-r_ot15_send_10.3.2.35'				=> 211531,
    'udpbench_-l36_-t10_-r_ot15_send_10.3.45.35'			=> 411531,
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34'				=> 211541,
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.45.34'			=> 411541,
    'udpbench_-l1452_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> 121511,
    'udpbench_-l1452_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> 121521,
    'udpbench_-l16_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> 121531,
    'udpbench_-l16_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> 121541,
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> 221511,
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> 421511,
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> 221521,
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> 421521,
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> 221531,
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> 421531,
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> 221541,
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> 421541,
    'udpbench_-l1472_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> 121512,
    'udpbench_-l1472_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> 121522,
    'udpbench_-l36_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> 121532,
    'udpbench_-l36_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> 121542,
    'udpbench_-l1472_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> 221512,
    'udpbench_-l1472_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> 421512,
    'udpbench_-l1472_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> 221522,
    'udpbench_-l1472_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> 421522,
    'udpbench_-l36_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> 221532,
    'udpbench_-l36_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> 421532,
    'udpbench_-l36_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> 221542,
    'udpbench_-l36_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> 421542,
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10'			=> 612151,
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10_-R'			=> 612161,
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-t10'				=> 612111,
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10'			=> 613151,
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10_-R'			=> 613161,
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10'	=> 622151,
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10_-R'	=> 622161,
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-t10'		=> 622111,
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10'	=> 623151,
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10_-R'	=> 623161,
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10'			=> 614151,
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10_-R'			=> 614161,
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10'			=> 615151,
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10_-R'			=> 615161,
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10'	=> 624151,
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10_-R'	=> 624161,
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10'	=> 625151,
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10_-R'	=> 625161,
    'time_-lp_make_-CGENERIC.MP_-j4_-s'					=> 800040,
    'time_-lp_make_-CGENERIC.MP_-j8_-s'					=> 800080,
    'time_-lp_fs_mark_-dfs_mark_-D8_-N16_-n256_-t8'			=> 900080,
);

%TESTORDER = @testorder;
if (2 * keys %TESTORDER != @testorder) {
    die "testorder keys not unique";
}
my %ordervalues = reverse @testorder;
if (2 * keys %ordervalues != @testorder) {
    my %dup;
    foreach (values %TESTORDER) {
	warn "duplicate testorder value $_\n" if ++$dup{$_} > 1;
    }
    die "testorder values not unique";
}
foreach (keys %TESTPLOT) {
    die "testplot $_ is not in testorder\n" unless $TESTORDER{$_};
}

########################################################################

our %TESTDESC;
# add a test description
my @testdesc = (
    'iperf3_-c10.3.45.35_-w1m_-t10'					=> "openbsd-openbsd-stack-tcp-ip3fwd",
    'iperf3_-c10.3.45.35_-w1m_-t10_-R'					=> "openbsd-openbsd-stack-tcp-ip3rev",
    'iperf3_-c10.3.0.33_-w1m_-t10'					=> "openbsd-openbsd-stack-tcp-ip3fwd-ot12",
    'iperf3_-c10.3.0.33_-w1m_-t10_-R'					=> "openbsd-openbsd-stack-tcp-ip3rev-ot12",
    'iperf3_-c10.3.0.33_-w1m_-t60'					=> "openbsd-openbsd-stack-tcp-ip3fwd-ot12",
    'iperf3_-c10.3.0.33_-w1m_-t60_-R'					=> "openbsd-openbsd-stack-tcp-ip3rev-ot12",
    'iperf3_-c10.3.2.35_-w1m_-t10'					=> "openbsd-openbsd-stack-tcp-ip3fwd-old",
    'iperf3_-c10.3.2.35_-w1m_-t10_-R'					=> "openbsd-openbsd-stack-tcp-ip3rev-old",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10'			=> "openbsd-openbsd-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-w1m_-t10_-R'			=> "openbsd-openbsd-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10'			=> "openbsd-openbsd-stack-tcp6-ip3fwd-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10_-R'			=> "openbsd-openbsd-stack-tcp6-ip3rev-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60'			=> "openbsd-openbsd-stack-tcp6-ip3fwd-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60_-R'			=> "openbsd-openbsd-stack-tcp6-ip3rev-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10'			=> "openbsd-openbsd-stack-tcp6-ip3fwd-old",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10_-R'			=> "openbsd-openbsd-stack-tcp6-ip3rev-old",
    'iperf3_-c10.3.46.36_-w2m_-t10'					=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.46.36_-w2m_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-t10'						=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-t60'						=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-t60_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-w1m_-t10'					=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-w1m_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-w2m_-t10'					=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-w2m_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-w400k_-t10'					=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-w400k_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-c10.3.3.36_-w410k_-t10'					=> "openbsd-linux-stack-tcp-ip3fwd",
    'iperf3_-c10.3.3.36_-w410k_-t10_-R'					=> "openbsd-linux-stack-tcp-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10'			=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0346::36_-w2m_-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10'				=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60'				=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10'			=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10'			=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10'			=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10'			=> "openbsd-linux-stack-tcp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10_-R'			=> "openbsd-linux-stack-tcp6-ip3rev",
    'tcpbench_-S1000000_-t10_10.3.45.35'				=> "openbsd-openbsd-stack-tcpbench-single",
    'tcpbench_-S1000000_-t10_10.3.0.33'					=> "openbsd-openbsd-stack-tcpbench-single-ot12",
    'tcpbench_-S1000000_-t10_10.3.2.35'					=> "openbsd-openbsd-stack-tcpbench-single-old",
    'tcpbench_-S1000000_-t60_10.3.0.33'					=> "openbsd-openbsd-stack-tcpbench-single-ot12",
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0345::35'			=> "openbsd-openbsd-stack-tcp6bench-single",
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0300::33'			=> "openbsd-openbsd-stack-tcp6bench-single-ot12",
    'tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0302::35'			=> "openbsd-openbsd-stack-tcp6bench-single-old",
    'tcpbench_-S1000000_-t60_fdd7:e83e:66bc:0300::33'			=> "openbsd-openbsd-stack-tcp6bench-single-ot12",
    'tcpbench_-S1000000_-t10_-n100_10.3.45.35'				=> "openbsd-openbsd-stack-tcpbench-parallel",
    'tcpbench_-S1000000_-t10_-n100_10.3.0.33'				=> "openbsd-openbsd-stack-tcpbench-parallel-ot12",
    'tcpbench_-S1000000_-t10_-n100_10.3.2.35'				=> "openbsd-openbsd-stack-tcpbench-parallel-old",
    'tcpbench_-S1000000_-t60_-n100_10.3.0.33'				=> "openbsd-openbsd-stack-tcpbench-parallel-ot12",
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0345::35'		=> "openbsd-openbsd-stack-tcp6bench-parallel",
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0300::33'		=> "openbsd-openbsd-stack-tcp6bench-parallel-ot12",
    'tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0302::35'		=> "openbsd-openbsd-stack-tcp6bench-parallel-old",
    'tcpbench_-S1000000_-t60_-n100_fdd7:e83e:66bc:0300::33'		=> "openbsd-openbsd-stack-tcp6bench-parallel-ot12",
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10'				=> "openbsd-openbsd-stack-udp-ip3fwd",
    'iperf3_-c10.3.45.35_-u_-b10G_-w1m_-t10_-R'				=> "openbsd-openbsd-stack-udp-ip3rev",
    'iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10'				=> "openbsd-openbsd-stack-udp-ip3fwd-ot12",
    'iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10_-R'				=> "openbsd-openbsd-stack-udp-ip3rev-ot12",
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10'				=> "openbsd-openbsd-stack-udp-ip3fwd-ot12",
    'iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R'				=> "openbsd-openbsd-stack-udp-ip3rev-ot12",
    'iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10'				=> "openbsd-openbsd-stack-udp-ip3fwd-old",
    'iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10_-R'				=> "openbsd-openbsd-stack-udp-ip3rev-old",
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10'				=> "openbsd-openbsd-stack-udp-ip3fwd-old",
    'iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R'				=> "openbsd-openbsd-stack-udp-ip3rev-old",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10'		=> "openbsd-openbsd-stack-udp6-ip3fwd",
    'iperf3_-6_-cfdd7:e83e:66bc:0345::35_-u_-b10G_-w1m_-t10_-R'		=> "openbsd-openbsd-stack-udp6-ip3rev",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10'		=> "openbsd-openbsd-stack-udp6-ip3fwd-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10_-R'		=> "openbsd-openbsd-stack-udp6-ip3rev-ot12",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10'		=> "openbsd-openbsd-stack-udp6-ip3fwd-old",
    'iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10_-R'		=> "openbsd-openbsd-stack-udp6-ip3rev-old",
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.45.34'			=> "openbsd-openbsd-stack-udpbench-long-recv",
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.45.35'			=> "openbsd-openbsd-stack-udpbench-long-send",
    'udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32'			=> "openbsd-openbsd-stack-udpbench-long-recv-ot12",
    'udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33'			=> "openbsd-openbsd-stack-udpbench-long-send-ot12",
    'udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34'			=> "openbsd-openbsd-stack-udpbench-long-recv-old",
    'udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35'			=> "openbsd-openbsd-stack-udpbench-long-send-old",
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.45.34'			=> "openbsd-openbsd-stack-udpbench-short-recv",
    'udpbench_-l36_-t10_-r_ot15_send_10.3.45.35'			=> "openbsd-openbsd-stack-udpbench-short-send",
    'udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32'				=> "openbsd-openbsd-stack-udpbench-short-recv-ot12",
    'udpbench_-l36_-t10_-r_ot13_send_10.3.0.33'				=> "openbsd-openbsd-stack-udpbench-short-send-ot12",
    'udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34'				=> "openbsd-openbsd-stack-udpbench-short-recv-old",
    'udpbench_-l36_-t10_-r_ot15_send_10.3.2.35'				=> "openbsd-openbsd-stack-udpbench-short-send-old",
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> "openbsd-openbsd-stack-udp6bench-long-recv",
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> "openbsd-openbsd-stack-udp6bench-long-send",
    'udpbench_-l1452_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> "openbsd-openbsd-stack-udp6bench-long-recv-ot12",
    'udpbench_-l1452_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> "openbsd-openbsd-stack-udp6bench-long-send-ot12",
    'udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "openbsd-openbsd-stack-udp6bench-long-recv-old",
    'udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "openbsd-openbsd-stack-udp6bench-long-send-old",
    'udpbench_-l1472_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "openbsd-openbsd-stack-udp6bench-long-recv-bad",
    'udpbench_-l1472_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "openbsd-openbsd-stack-udp6bench-long-send-bad",
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0345::34'		=> "openbsd-openbsd-stack-udp6bench-short-recv",
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0345::35'		=> "openbsd-openbsd-stack-udp6bench-short-send",
    'udpbench_-l16_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32'		=> "openbsd-openbsd-stack-udp6bench-short-recv-ot12",
    'udpbench_-l16_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33'		=> "openbsd-openbsd-stack-udp6bench-short-send-ot12",
    'udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "openbsd-openbsd-stack-udp6bench-short-recv-old",
    'udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "openbsd-openbsd-stack-udp6bench-short-send-old",
    'udpbench_-l36_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34'		=> "openbsd-openbsd-stack-udp6bench-short-recv-bad",
    'udpbench_-l36_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35'		=> "openbsd-openbsd-stack-udp6bench-short-send-bad",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10'			=> "linux-openbsd-linux-forward-tcp-ip3fwd",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-P10_-t10_-R'			=> "linux-openbsd-linux-forward-tcp-ip3rev",
    'ssh_perform@lt13_iperf3_-c10.3.46.36_-t10'				=> "linux-openbsd-linux-forward-tcp-ip3fwd-single",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10'	=> "linux-openbsd-linux-forward-tcp6-ip3fwd",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-P10_-t10_-R'	=> "linux-openbsd-linux-forward-tcp6-ip3rev",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0346::36_-t10'		=> "linux-openbsd-linux-forward-tcp6-ip3fwd-single",
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10'			=> "linux-openbsd-linux-splice-tcp-ip3fwd",
    'ssh_perform@lt13_iperf3_-c10.3.34.34_-P10_-t10_-R'			=> "linux-openbsd-linux-splice-tcp-ip3rev",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10'	=> "linux-openbsd-linux-splice-tcp6-ip3fwd",
    'ssh_perform@lt13_iperf3_-6_-cfdd7:e83e:66bc:0334::34_-P10_-t10_-R'	=> "linux-openbsd-linux-splice-tcp6-ip3rev",
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10'			=> "linux-openbsd-openbsd-splice-tcp-ip3fwd",
    'ssh_perform@lt16_iperf3_-c10.3.46.34_-P10_-t10_-R'			=> "linux-openbsd-openbsd-splice-tcp-ip3rev",
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10'			=> "linux-openbsd-splice-tcp-ip3fwd",
    'ssh_perform@lt16_iperf3_-c10.3.56.35_-P10_-t10_-R'			=> "linux-openbsd-splice-tcp-ip3rev",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10'	=> "linux-openbsd-openbsd-splice-tcp6-ip3fwd",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0346::34_-P10_-t10_-R'	=> "linux-openbsd-openbsd-splice-tcp6-ip3rev",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10'	=> "linux-openbsd-splice-tcp6-ip3fwd",
    'ssh_perform@lt16_iperf3_-6_-cfdd7:e83e:66bc:0356::35_-P10_-t10_-R'	=> "linux-openbsd-splice-tcp6-ip3rev",
    'time_-lp_make_-CGENERIC.MP_-j4_-s'					=> "make-bsd",
    'time_-lp_make_-CGENERIC.MP_-j8_-s'					=> "make-bsd-ot12",
    'time_-lp_fs_mark_-dfs_mark_-D8_-N16_-n256_-t8'			=> "file-system",
);

%TESTDESC = @testdesc;
if (2 * keys %TESTDESC != @testdesc) {
    die "testdesc keys not unique";
}
my %num;
for (my $i = 0; $i < @testdesc; $i += 2) {
    my ($test, $desc) = @testdesc[$i, $i + 1];
    if ($num{$desc}) {
	$TESTDESC{$test} = "$desc-$num{$desc}";
    }
    $num{$desc}++;
}
foreach (keys %TESTPLOT) {
    die "testplot $_ is not in testdesc\n" unless $TESTDESC{$_};
}
foreach (keys %TESTDESC) {
    die "testdesc $_ is not in testorder\n" unless $TESTORDER{$_};
}

########################################################################

1;
