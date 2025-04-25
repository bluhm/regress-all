# put common statistics parsing functions in a module

# Copyright (c) 2025 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2023 Moritz Buhl <mbuhl@genua.de>
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

package Kstat;

use strict;
use warnings;

use parent 'Exporter';
our @EXPORT= qw(
    kstat_diff
    generate_diff_kstat
);

# map kstat indentation to perl hash
sub parse {
    my ($file) = @_;
    my %kstat;
    open(my $fh, '<', $file)
	or die "Open '$file' for reading failed: $!";

    my ($l1, $l2);
    while(<$fh>) {
	chomp;
	if (m{^([\w:-]+)$}) {
	    $l1 = $1;
	    $kstat{$l1} = {};
	} elsif (m{^( +)([^:]+:) ((\d+)(?: (\w+))?|.*)$}) {
	    $l2 = $2;
	    $kstat{$l1}{$l2}{indent} = $1;
	    $kstat{$l1}{$l2}{string} = $3;
	    $kstat{$l1}{$l2}{value} = $4;
	    $kstat{$l1}{$l2}{unit} = $5;
	} else {
	    die "Cannot parse '$_'";
	}
    }

    return %kstat;
}

# iterate over all key value pairs and print them
sub myprint {
    my ($fh, $l1) = @_;
    my %res;
    foreach my $k1 (sort keys %$l1) {
	print $fh "$k1\n";
	my $l2 = $l1->{$k1};
	if (ref($l2) eq 'HASH') {
	    foreach my $k2 (sort keys %$l2) {
		my $l3 = $l2->{$k2};
		print $fh "$l3->{indent}$k2 ",
		    defined $l3->{value} ?
			defined $l3->{unit} ?
			    "$l3->{value} $l3->{unit}" :
			    "$l3->{value}" :
			"$l3->{string}",
		    "\n";
	    }
	} else {
	    print $fh "$k1 $l2\n";
	}
    }
}

# iterate over all keys and subtract values. Only save the ones greater than 0
sub diff {
    my ($l1, $m1) = @_;
    my %res;
    foreach my $k1 (keys %$l1) {
	my $l2 = $l1->{$k1};
	if (ref($l2) eq 'HASH') {
	    my $m2 = $m1->{$k1};
	    my $r2 = $res{$k1} ||= {};
	    foreach my $k2 (keys %$l2) {
		my $l3 = $l2->{$k2};
		my $m3 = $m2->{$k2};
		if (defined $l3->{value}) {
		    if ($l3->{value} != $m3->{value}) {
			$r2->{$k2} = $l3;
			$r2->{$k2}{value} = $m3->{value} - $l3->{value};
		    }
		} else {
		    if ($l3->{string} ne $m3->{string}) {
			$r2->{$k2} = $l3;
			$r2->{$k2}{string} = "$l3->{string} -> $m3->{string}";
		    }
		}
	    }
	}
    }
    return %res;
}

# remove empty key-hash pairs
sub sweep {
    my ($l1) = @_;
    foreach my $k1 (keys %$l1) {
	my $l2 = $l1->{$k1};
	if (ref($l2) eq 'HASH') {
	    delete $l1->{$k1} unless keys %$l2;
	}
    }
}

sub kstat_diff {
    my ($fh, $test, $arg) = @_;

    my $before = "$test.stats-kstat_$arg-before.txt";
    my $after = "$test.stats-kstat_$arg-after.txt";
    -r $before && -r $after
	or return;
    my %bef = parse($before);
    my %aft = parse($after);
    my %dif = diff(\%bef, \%aft);
    # better always show the caption
    #sweep(\%dif);
    myprint($fh, \%dif);
}

sub generate_diff_kstat {
    my ($test, $arg) = @_;

    my $diff = "$test.stats-kstat_$arg-diff.txt";
    open(my $fh, '>', $diff)
	or die "Open '$diff' for writing failed: $!";
    kstat_diff($fh, $test, $arg);
    close($fh)
	or die "Close '$diff' after writing failed: $!";
}

1;
