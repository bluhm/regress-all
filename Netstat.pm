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

package Netstat;

use strict;
use warnings;

use parent 'Exporter';
our @EXPORT= qw(
    netstat_diff
    generate_diff_netstat
);

# netstat output might use plural for some nouns always use
# the plural form of these words.
sub canonicalize_key {
    my ($key) = @_;
    my @plurales = qw(miss);
    my @pluralys = qw(entr);
    my @plurals = qw(ACK Interface SYN TDB accept ack agreement allocation
	association attempt authentication byte calculation call change
	checksum cleanup collision connection datagram decapsulation
	decryption destination drop duplicate episode error failure field
	flow fragment frame gap gateway global insert jump llx local
	lookup mbuf message mismatche node notification option overflow
	packet prediction probe quer redirect replay report request
	response rexmit route scan seed segment slide state table
	timeout transition upcall use);

    foreach my $sub (@plurales) {
	$key =~ s/ ${sub}(?=[^e][^s])/ ${sub}es/;
	$key =~ s/^${sub}(?=[^e][^s])/${sub}es/;
    }
    foreach my $sub (@pluralys) {
	$key =~ s/ ${sub}(?=[^i][^e][^s])/ ${sub}ies/;
	$key =~ s/^${sub}(?=[^i][^e][^s])/${sub}ies/;
    }
    foreach my $sub (@plurals) {
	$key =~ s/ ${sub}(?=[^s])/ ${sub}s/;
	$key =~ s/^${sub}(?=[^s])/${sub}s/;
    }

    chomp $key;
    return $key;
}

# map netstat indentation to perl hash some nestat -s lines increase the
# indentation and at the same time have a value.  Write that value to the
# "total" field.
sub parse_s {
    my ($fname) = @_;
    my %netstat;
    my $l1;
    my $l2;
    my $l3;
    open(my $fh, '<', $fname)
	or die "Open '$fname' for reading failed: $!";

    while(<$fh>) {
	chomp;
	if (m{^(\w+):$}) {
	    $l1 = canonicalize_key $1;
	    $netstat{$l1} = {}
	} elsif (m{^			([^:	]+): (\d+)$}) {
	    my $k = canonicalize_key($1);
	    if (ref($netstat{$l1}{$l2}{$l3}) ne "HASH") {
		my $total = $netstat{$l1}{$l2}{$l3};
		$netstat{$l1}{$l2}{$l3} = {};
		$netstat{$l1}{$l2}{$l3}{total} = $total;
	    }
	    $netstat{$l1}{$l2}{$l3}{$k} = $2;
	} elsif (m{^		(\d+) (.+)$}) {
	    $l3 = canonicalize_key $2;
	    my $v = $1;
	    if (ref($netstat{$l1}{$l2}) ne "HASH") {
		my $total = $netstat{$l1}{$l2};
		$netstat{$l1}{$l2} = {};
		$netstat{$l1}{$l2}{total} = $total;
	    }
	    if ($l3 =~ m{\((.+)\)} && $1 =~ /\d/) {
		my ($l) = $l3 =~ /\((.+)\)/;
		$l3 =~ s/ \(.+\)//;
		(my $k2 = "$l3 $l") =~ s/\d+ //;
		$k2 = canonicalize_key $k2;
		my ($v2) = $l =~ /(\d+)/;
		$netstat{$l1}{$l2}{$k2} = $v2;
	    }
	    $netstat{$l1}{$l2}{$l3} = $v;
	} elsif (m{^		([^:]+): (\d+)$}) {
	    $l3 = canonicalize_key $1;
	    $netstat{$l1}{$l2}{$l3} = $2;
	} elsif (m{^	(\d+) (.+)$}) {
	    my $v = $1;
	    $l2 = canonicalize_key $2;
	    if ($l2 =~ m{\((.+)\)} && $1 =~ /\d/) {
		my ($l) = $l2 =~ /\((.+)\)/;
		$l2 =~ s/ \(.+\)//;
		(my $k2 = "$l2 $l") =~ s/\d+ //;
		$k2 = canonicalize_key $k2;
		my ($v2) = $l =~ /(\d+)/;
		$netstat{$l1}{$k2} = $v2;
	    }
	    $netstat{$l1}{$l2} = $v;
	} elsif (m{^	([^:]+):?$}) {
	    $l2 = canonicalize_key $1;
	    $netstat{$l1}{$l2} = {};
	} else {
	    die "Cannot parse '$_'";
	}
    }

    return %netstat;
}

sub parse_m {
    my ($fname) = @_;
    my %netstat;
    my $l1 = "memory";
    my $l2;
    my $l3;
    open(my $fh, '<', $fname)
	or die "Open '$fname' for reading failed: $!";

    while(<$fh>) {
	if (m{^(\d+) mbufs? (in use):}) {
	    $l2 = "mbuf $2";
	    $netstat{$l1}{$l2} = $1;
	    $l2 = "mbuf types";
	} elsif (m{^	(\d+) mbufs? (allocated to .+)}) {
	    $l3 = "mbuf $2";
	    $netstat{$l1}{$l2}{$l3} = $1;
	} elsif (m{^(\d+)/\d+ (mbuf \d+ byte clusters in use)}) {
	    $l2 = "mbuf cluster in use";
	    $l3 = $2;
	    $netstat{$l1}{$l2}{$l3} = $1;
	} elsif (m{^(\d+)/\d+/\d+ (Kbytes allocated to network)}) {
	    $l2 = $2;
	    $netstat{$l1}{$l2} = $1;
	} elsif (m{^(\d+) (\w[\w ]+)$}) {
	    $l2 = "counter";
	    $l3 = $2;
	    $netstat{$l1}{$l2}{$l3} = $1;
	}
    }

    return %netstat;
}

# iterate over all key value pairs and print them
sub myprint {
    my ($fh, $l1) = @_;
    my %res;
    foreach my $k (sort keys %$l1) {
	print $fh ("$k:\n");
	if (ref($l1->{$k}) eq "HASH") {
	    my $l2 = $l1->{$k};
	    foreach my $k2 (sort keys %$l2) {
		if (ref($l2->{$k2}) eq "HASH") {
		    print $fh ("\t$k2:\n");
		    my $l3 = $l2->{$k2};
		    foreach my $k3 (sort keys %$l3) {
			if (ref($l3->{$k3}) eq "HASH") {
			    my $l4 = $l3->{$k3};
			    print $fh ("\t\t$k3:\n");
			    foreach my $k4 (sort keys %$l4) {
				print $fh ("\t\t\t$k4: $l4->{$k4}\n");
			    }
			} else {
			    print $fh ("\t\t$k3: $l3->{$k3}\n");
			}
		    }
		} else {
		    print $fh ("\t$k2: $l2->{$k2}\n");
		}
	    }
	} else {
	    print $fh ("$k: $l1->{$k}\n");
	}
    }
}

# iterate over all keys and subtract values. Only save the ones greater than 0
sub diff {
    my ($l1, $m1) = @_;
    my %res;
    foreach my $k (sort keys %$l1) {
	if (ref($l1->{$k}) eq "HASH") {
	    $res{$k} = {};
	    my $l2 = $l1->{$k};
	    my $m2 = $m1->{$k};
	    foreach my $k2 (sort keys %$l2) {
		if (ref($l2->{$k2}) eq "HASH") {
		    $res{$k}{$k2} = {};
		    my $l3 = $l2->{$k2};
		    my $m3 = $m2->{$k2};
		    foreach my $k3 (sort keys %$l3) {
			if (ref($l3->{$k3}) eq "HASH") {
			    $res{$k}{$k2}{$k3} = {};
			    my $l4 = $l3->{$k3};
			    my $m4 = $m3->{$k3};
			    foreach my $k4 (sort keys %$l4) {
				my $v = $m4->{$k4} - $l4->{$k4};
				$res{$k}{$k2}{$k3}{$k4} = $v if ($v != 0);
			    }
			} else {
			    my $v = $m3->{$k3} - $l3->{$k3};
			    $res{$k}{$k2}{$k3} = $v if ($v != 0);
			}
		    }
		} else {
		    my $v = $m2->{$k2} - $l2->{$k2};
		    $res{$k}{$k2} = $v if ($v != 0);
		}
	    }
	} else {
	    my $v = $m1->{$k} - $l1->{$k};
	    $res{$k} = $v if ($v != 0);
	}
    }
    return %res;
}

# remove empty key-hash pairs
sub sweep {
    my ($l1) = @_;
    foreach my $k1 (sort keys %$l1) {
	my $l2 = $l1->{$k1};
	if (ref($l2) eq "SCALAR") {
	    delete $l1->{$k1} if ($l2 == 0);
	} elsif (ref($l2) eq "HASH") {
	    foreach my $k2 (sort keys %$l2) {
		my $l3 = $l2->{$k2};
		if (ref($l3) eq "SCALAR") {
		    delete $l2->{$k2} if ($l3 == 0);
		} elsif (ref($l3) eq "HASH") {
		    foreach my $k3 (sort keys %$l3) {
			my $l4 = $l3->{$k3};
			if (ref($l4) eq "SCALAR") {
			    delete $l3->{$k3} if ($l4 == 0);
			} elsif (ref($l4) eq "HASH") {
			    foreach my $k4 (sort keys %$l4) {
				my $l5 = $l4->{$k4};
				delete $l4->{$k4} if ($l5 == 0);
			    }
			    delete $l3->{$k3} if (scalar (keys %$l4) == 0);
			}
		    }
		    delete $l2->{$k2} if (scalar (keys %$l3) == 0);
		}
	    }
	}
	delete $l1->{$k1} if (scalar (keys %$l2) == 0);
    }
}

sub netstat_diff {
    my ($fh, $test, $opt) = @_;

    my $before = "$test.stats-netstat_-$opt-before.txt";
    my $after = "$test.stats-netstat_-$opt-after.txt";
    -r $before && -r $after
	or return;
    my $parser;
    $parser = \&parse_m if $opt eq 'm';
    $parser = \&parse_s if $opt eq 's';
    my %bef = $parser->($before);
    my %aft = $parser->($after);
    my %dif = diff(\%bef, \%aft);
    sweep(\%dif);
    myprint($fh, \%dif);
}

sub generate_diff_netstat {
    my ($test) = @_;

    my $diff = "$test.stats-netstat-diff.txt";
    open(my $fh, '>', $diff)
	or die "Open '$diff' for writing failed: $!";
    foreach my $opt (qw(m s)) {
	netstat_diff($fh, $test, $opt);
    }
    close($fh)
	or die "Close '$diff' after writing failed: $!";
}

1;
