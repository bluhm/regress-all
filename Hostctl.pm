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
use Machine;

use parent 'Exporter';
our @EXPORT= qw(usehosts setup_hosts
    collect_version collect_dmesg collect_result
    cvsbuild_hosts reorder_kernel
);

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

	if ($mode{install} || $mode{upgrade}) {
	    # create new summary with setup log
	    sleep 5;
	    runcmd("$bindir/setup-html.pl");

	    # change config of dhcpd has races, cannot install simultaneously
	    waitcmd(@pidcmds);
	    undef @pidcmds;
	}
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	runcmd("$bindir/setup-html.pl");

	waitcmd(@pidcmds);
    }
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

sub collect_dmesg {
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my $dmesg = "dmesg-$host.txt";
	eval { logcmd({
	    cmd => ['ssh', "$user\@$host", 'dmesg'],
	    outfile => $dmesg,
	})};
	if ($@) {
	    unlink $dmesg;
	    last;
	}
    }
}

sub collect_result {
    foreach my $source (@_) {
	my @scpcmd = ('scp');
	push @scpcmd, '-q' unless $verbose;
	push @scpcmd, ("$source/test.*", ".");
	runcmd(@scpcmd);

	open(my $tr, '<', "test.result")
	    or die "Open 'test.result' for reading failed: $!";
	my $logdir = "logs";
	mkdir $logdir
	    or die "Make directory '$logdir' failed: $!";
	chdir($logdir)
	    or die "Chdir to '$logdir' failed: $!";
	my @paxcmd = ('pax', '-rzf', "../test.log.tgz");
	open(my $pax, '|-', @paxcmd)
	    or die "Open pipe to '@paxcmd' failed: $!";
	while (<$tr>) {
	    my ($status, $test, $message) = split(" ", $_, 3);
	    print $pax $test unless $test =~ m,[^\w/],;
	}
	close($pax) or die $! ?
	    "Close pipe to '@paxcmd' failed: $!" :
	    "Command '@paxcmd' failed: $?";
	close($tr)
	    or die "Close 'test.result' after reading failed: $!";

	chdir("..")
	    or die "Chdir to '..' failed: $!";
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
	    '-h', "$user\@$host", '-d', $date, '-D', $cvsdate);
	push @cvscmd, '-v' if $verbose;
	push @pidcmds, forkcmd(@cvscmd);
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	runcmd("$bindir/setup-html.pl");

	waitcmd(@pidcmds);
    }
}

sub reorder_kernel {
    my $cksum = "/var/db/kernel.SHA256";
    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my $relinkcmd =
	    "sha256 -h $cksum /bsd; usr/libexec/reorder_kernel; rm $cksum";
	my @sshcmd = ('ssh', "$user\@$host", $relinkcmd);
	push @pidcmds, forkcmd(@sshcmd);
    }
    waitcmd(@pidcmds);
    undef @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @sshcmd = ('ssh', "$host\@$Machine::testmaster", "reboot");
	push @pidcmds, forkcmd(@sshcmd);
    }
    waitcmd(@pidcmds);
}

1;
