# functions to control a set of hosts

# Copyright (c) 2018-2023 Alexander Bluhm <bluhm@genua.de>
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
    cvsbuild_hosts powerdown_hosts powerup_hosts reboot_hosts
    setup_html
);

my %lasthosts = (
    ot1  => "ot4",
    ot10 => "ot11",
    ot14 => "ot15",
    ot31 => "ot32",
);

my ($bindir, $user, $firsthost, $lasthost, $date, $verbose);

sub usehosts {
    my %args = @_;
    ($bindir, $date, $verbose) = delete @args{qw(bindir date verbose)};
    ($user, $firsthost) = split('@', delete $args{host}, 2);
    ($user, $firsthost) = ("root", $user) unless $firsthost;
    if ($args{lasthost}) {
	$lasthost = delete $args{lasthost};
	$lasthost =~ s/.*@//;
    }
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    $lasthost ||= $lasthosts{$firsthost} || $firsthost
	and return;
    for (my $host = $firsthost;
	-f "$bindir/pkg-$host.list";
	$lasthost = $host++) {
	    # XXX hack to find out whether a remote machine exists
    }
}

sub setup_hosts {
    my %args = @_;
    my $patch = delete $args{patch};
    my $release = delete $args{release};
    my %mode = %{delete $args{mode}};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @setupcmd = ("$bindir/setup.pl", '-h', "$user\@$host");
	push @setupcmd, '-d', $date if $date;
	push @setupcmd, '-v' if $verbose;
	push @setupcmd, '-P', $patch if $patch;
	push @setupcmd, '-r', $release if $release;
	push @setupcmd, keys %mode;
	push @pidcmds, forkcmd(@setupcmd);

	if ($mode{install} || $mode{upgrade} || $mode{sysupgrade}) {
	    # create new summary with setup log
	    sleep 5;
	    setup_html();
	}
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	setup_html();
	my @cmd = ("$bindir/running-html.pl");
	system(@cmd);

	waitcmd(@pidcmds);
    }
}

sub collect_version {
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my $version = "version-$host.txt";
	logeval { logcmd({
	    cmd => ['ssh', "$user\@$host", 'sysctl',
		'kern.version', 'hw.machine', 'hw.ncpu'],
	    outfile => $version,
	})};
	if ($@) {
	    unlink $version;
	    last;
	}
	my $dmesg = "dmesg-boot-$host.txt";
	logeval { logcmd({
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
	logeval { get_bsdcons() };
	last if $@;
    }
}

sub collect_dmesg {
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my $dmesg = "dmesg-$host.txt";
	logeval { logcmd({
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
	-d $logdir || mkdir $logdir
	    or die "Make directory '$logdir' failed: $!";
	chdir($logdir)
	    or die "Change directory to '$logdir' failed: $!";
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
	    or die "Change directory to '..' failed: $!";
    }
}

sub hosts_command {
    my ($command, %args) = @_;
    my $cvsdate = delete $args{cvsdate};
    my $patch = delete $args{patch};
    my $modify = delete $args{modify};
    my $release = delete $args{release};
    my $repeatdir = delete $args{repeatdir};
    my %mode = %{delete $args{mode} || {}};
    my @unknown = keys %args;
    croak "Unknown args: @unknown" if @unknown;

    my @pidcmds;
    for (my $host = $firsthost; $host le $lasthost; $host++) {
	my @cmd = ("$bindir/$command", '-h', "$user\@$host");
	push @cmd, '-d', $date if $date;
	push @cmd, '-D', $cvsdate if $cvsdate;
	push @cmd, '-P', $patch if $patch;
	push @cmd, '-m', $modify if $modify;
	push @cmd, '-r', $release if $release;
	push @cmd, '-R', $repeatdir if $repeatdir;
	push @cmd, '-v' if $verbose;
	push @cmd, keys %mode;
	push @pidcmds, forkcmd(@cmd);
    }
    if (@pidcmds) {
	# create new summary with setup log
	sleep 5;
	setup_html();

	waitcmd(@pidcmds);
    }
}

sub cvsbuild_hosts {
    hosts_command("cvsbuild.pl", @_);
}

sub powerdown_hosts {
    hosts_command("power.pl", @_, mode => { down => 1 });
}

sub powerup_hosts {
    hosts_command("power.pl", @_, mode => { up => 1 });
}

sub reboot_hosts {
    hosts_command("reboot.pl", @_);
}

# there may be races with other running instances, make it non fatal
sub setup_html {
    my %args = @_;
    my @cmd = ("$bindir/setup-html.pl");
    push @cmd, '-a' if $args{all};
    push @cmd, '-d', $date if $args{date};
    logeval { runcmd(@cmd) };
}

1;
