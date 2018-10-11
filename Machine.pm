# functions to manipulate remote test machine

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

package Machine;

use strict;
use warnings;
use Carp;
use Date::Parse;
use POSIX;

use Logcmd;

use parent 'Exporter';
our @EXPORT= qw(createhost reboot
    install_pxe upgrade_pxe get_version
    checkout_cvs update_cvs diff_cvs
    make_kernel make_build
);

# XXX explicit IP address in source code
our $testmaster = "10.0.1.1";

my ($user, $host, %sysctl);

sub createhost {
    ($user, $host) = @_;
}

# reboot machine

sub reboot {
    logcmd('ssh', "$host\@$testmaster", "reboot");
}

# pxe install machine

sub install_pxe {
    my ($release) = @_;
    logcmd('ssh', "$host\@$testmaster", "install", $release || ());
}

sub upgrade_pxe {
    logcmd('ssh', "$host\@$testmaster", "upgrade");
}

# get version information

sub get_version {
    my @sshcmd = (('ssh', "$user\@$host", 'sysctl'),
	qw(kern.version hw.machine hw.ncpu));
    logmsg "Command '@sshcmd' started\n";
    open(my $ctl, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $version, '>', "version-$host.txt")
	or die "Open 'version-$host.txt' for writing failed: $!";
    %sysctl = ();
    my $prevkey;
    local $_;
    while (defined($_ = <$ctl>)) {
	if (m{^([\w.]+)=(.*)}) {
	    $sysctl{$1} = $2;
	    $prevkey = $1;
	} else {
	    $sysctl{$prevkey} .= "\n$_";
	}
	print $version $_;
    }
    close($ctl) or die $! ?
	"Close pipe from '@sshcmd' failed: $!" :
	"Command '@sshcmd' failed: $?";
    logmsg "Command '@sshcmd' finished\n";
    return %sysctl;
}

# cvs checkout, update, diff

sub checkout_cvs {
    my ($release) = @_;
    foreach (qw(src ports xenocara)) {
	logcmd('ssh', "$user\@$host",
	    "cd /usr && cvs -Rd /mount/openbsd/cvs co $_/Makefile")
    }
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/ -rOPENBSD_${1}_${2}_BASE/;
    logcmd('ssh', "$user\@$host", "cd /usr/src && cvs -R up -PdA$tag");
    logcmd('ssh', "$user\@$host", "cd /usr/src && make obj");
}

sub update_cvs {
    my ($release, $date, $path) = @_;
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/ -rOPENBSD_${1}_${2}_BASE/;
    $tag = $date ? strftime(" -D%FZ%T", gmtime(str2time($date))) : "";
    $path = $path ? " $path" : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && cvs -qR up -PdAC$tag$path");
    $path = $path ? " -C$path" : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && make$path obj");
}

sub diff_cvs {
    my ($path) = @_;
    $path = $path ? " $path" : "";
    my @sshcmd = ('ssh', "$user\@$host",
	"cd /usr/src && cvs -qR diff -up$path");
    logmsg "Command '@sshcmd' started\n";
    open(my $cvs, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $diff, '>', "diff-$host.txt")
	or die "Open 'diff-$host.txt' for writing failed: $!";
    local $_;
    while (<$cvs>) {
	print $diff $_;
    }
    close($cvs) or do {
	die "Close pipe from '@sshcmd' failed: $!" if $!;
	# cvs diff returns 0 without and 1 with differences
	die "Command '@sshcmd' failed: $?" if $? != 0 && $? != (1<<8);
    };
    logmsg "Command '@sshcmd' finished\n";
}

# make /usr/src

sub make_kernel {
    my $version = $sysctl{'kern.version'};
    $version =~ m{:/usr/src/sys/([\w./]+)$}m
	or die "No kernel path in version: $version";
    my $path = $1;
    my $ncpu = $sysctl{'hw.ncpu'};
    my $jflag = $ncpu > 1 ? " -j ".($ncpu+1) : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make config");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make clean")
	if loggrep(qr/you must run "make clean"/);
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && if [ -s CVS/Tag ]".
	"; then echo -n 'cvs : '; cat CVS/Tag; fi >obj/version");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && nice make$jflag");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make install");
    # disable kernel relinking, load after reboot may change perform result
    logcmd('ssh', "$user\@$host", "rm /var/db/kernel.SHA256");
}

sub make_build {
    my $ncpu = $sysctl{'hw.ncpu'};
    my $jflag = $ncpu > 1 ? " -j ".($ncpu+1) : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && nice make$jflag build");
}

1;
