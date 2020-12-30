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
our @EXPORT= qw(
    usehosts setup_hosts
    collect_version collect_bsdcons collect_dmesg collect_result
    cvsbuild_hosts reboot_hosts
    setup_html
);

my %lasthosts = (
    ot1  => "ot4",
    ot6  => "ot6",
    ot7  => "ot7",
    ot10 => "ot11",
    ot11 => "ot11",
    ot12 => "ot13",
    ot14 => "ot15",
    ot18 => "ot18",
);

my ($bindir, $user, $firsthost, $lasthost, $date, $verbose);

sub usehosts {
    my %args = @_;
    ($bindir, $date, $verbose) = delete @args{qw(bindir date verbose)};
    ($user, $firsthost) = split('@', delete $args{host}, 2);
    ($user, $firsthost) = ("root", $user) unless $firsthost;
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    $lasthost = $lasthosts{$firsthost}
	and return;
    for (my $host = $firsthost;
	-f "$bindir/pkg-$host.list";
	$lasthost = $host++) {
	    # XXX hack to find out whether a remote machine exists
    }
}

sub setup_hosts {
    my %args = @_;
    my $release = delete $args{release};
    my %mode = %{delete $args{mode}};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    my $num = 0;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	$num++;
	if ($mode{build} && $num > 2) {
	    # only build on first two hosts, ot4 is too slow
	    next;
	}

	my @setupcmd = ("$bindir/setup.pl", '-h', "$user\@$host");
	push @setupcmd, '-d', $date if $date;
	push @setupcmd, '-v' if $verbose;
	push @setupcmd, '-r', $release if $release;
	push @setupcmd, keys %mode;
	push @pidcmds, forkcmd(@setupcmd);

	if ($mode{install} || $mode{upgrade}) {
	    # create new summary with setup log
	    sleep 5;
	    setup_html();
	}
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	setup_html();

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

sub collect_bsdcons {
    return if !$bindir;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	createhost($user, $host);
	eval { get_bsdcons() };
	if ($@) {
	    logmsg("WARNING: $@");
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
	    next if $status =~ /VALUE/;
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
    my %mode = %{delete $args{mode}};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @cvscmd = ("$bindir/cvsbuild.pl", '-h', "$user\@$host");
	push @cvscmd, '-d', $date if $date;
	push @cvscmd, '-D', $cvsdate if $cvsdate;
	push @cvscmd, '-v' if $verbose;
	push @cvscmd, keys %mode;
	push @pidcmds, forkcmd(@cvscmd);
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	setup_html();

	waitcmd(@pidcmds);
    }
}

sub reboot_hosts {
    my %args = @_;
    my $cvsdate = delete $args{cvsdate};
    my $repeat = delete $args{repeat};
    my %mode = %{delete $args{mode}};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @rebootcmd = ("$bindir/reboot.pl", '-h', "$user\@$host");
	push @rebootcmd, '-d', $date if $date;
	push @rebootcmd, '-D', $cvsdate if $cvsdate;
	push @rebootcmd, '-R', $repeat if $repeat;
	push @rebootcmd, '-v' if $verbose;
	push @rebootcmd, keys %mode;
	push @pidcmds, forkcmd(@rebootcmd);
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	setup_html();

	waitcmd(@pidcmds);
    }
}

# there may be races with other running instances, make it non fatal
sub setup_html {
    my %args = @_;
    my @cmd = ("$bindir/setup-html.pl");
    push @cmd, '-a' if $args{all};
    push @cmd, '-d', $date if $args{date};
    eval { runcmd(@cmd) };
    logmsg("WARNING: $@") if $@;
}

1;
