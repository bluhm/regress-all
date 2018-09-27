# functions to control a set of hosts

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
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

package Hostctl;

use strict;
use warnings;
use Carp;

use Logcmd;

use parent 'Exporter';
our @EXPORT= qw(usehosts setup_hosts collect_version cvsbuild_hosts);

my ($bindir, $user, $firsthost, $lasthost, $date, $verbose);

sub usehosts {
    my %args = @_;
    ($bindir, $date, $verbose) = delete @args{qw(bindir date verbose)};
    ($user, $firsthost) = split('@', delete $args{host}, 2);
    ($user, $firsthost) = ("root", $user) unless $firsthost;
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    for (my $host = $firsthost;
	-f "$bindir/pkg-$host.list";
	$lasthost = $host++) {
	    # XXX hack to find out whether a remote machine exists
    }
    return $user;
}

sub setup_hosts {
    my %args = @_;
    my %mode = %{delete $args{mode}};
    my $release = delete $args{release};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @setupcmd = ("$bindir/setup.pl", '-h', "$user\@$host", '-d', $date);
	push @setupcmd, '-v' if $verbose;
	push @setupcmd, '-r', $release if $release;
	push @setupcmd, keys %mode;
	push @pidcmds, forkcmd(@setupcmd);

	# create new summary with setup log
	sleep 1;
	runcmd("$bindir/setup-html.pl");

	if ($mode{install} || $mode{upgrade}) {
	    # change config of dhcpd has races, cannot install simultaneously
	    waitcmd(@pidcmds);
	    undef @pidcmds;
	}
    }
    waitcmd(@pidcmds);
}

sub collect_version {
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my $version = "version-$host.txt";
	eval { logcmd({
	    cmd => ['ssh', "$user\@$host", 'sysctl',
		'kern.version', 'hw.machine', 'hw.ncpu'],
	    outfile => $version,
	})};
	if ($@) {
	    unlink $version;
	    last;
	}
	my $dmesg = "dmesg-boot-$host.txt";
	eval { logcmd({
	    cmd => ['ssh', "$user\@$host", 'cat', '/var/run/dmesg.boot'],
	    outfile => $dmesg,
	})};
	if ($@) {
	    unlink $dmesg;
	    last;
	}
    }
}

sub cvsbuild_hosts {
    my %args = @_;
    my $cvsdate = delete $args{cvsdate};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @cvscmd = ("$bindir/cvsbuild.pl",
	    '-h', "$user\@$host", '-D', $cvsdate);
	push @cvscmd, '-v' if $verbose;
	push @pidcmds, forkcmd(@cvscmd);
    }
    waitcmd(@pidcmds);
}

1;
