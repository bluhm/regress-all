#!/usr/bin/perl
# setup machine for regress test

# Copyright (c) 2016-2017 Alexander Bluhm <bluhm@genua.de>
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
use Cwd;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;

# XXX explicit IP address in source code
my $testmaster="10.0.1.1";

my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:h:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] -h host [-r relese] mode ...
    -d date	set date string and change to sub directory
    -h host	root\@openbsd-test-machine, login per ssh
    -r release	use release for install and cvs checkout
    -v		verbose
    build	build system from source /usr/src
    cvs		clean cvs update /usr/src and make obj
    install	install from snapshot
    kernel	build kernel from source /usr/src/sys
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};

my %allmodes;
@allmodes{qw(build cvs install kernel upgrade)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(install upgrade)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}
my $release;
if ($opts{r}) {
    die "Upgrade to release not supported" if $mode{upgrade};
    $release = $opts{r};
    die "Release must be major.minor" unless $release =~ /^\d.\d$/;
}

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Chdir to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results";
$resultdir .= "/$date" if $date;
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";
my $bindir = "$regressdir/bin";

(my $host = $opts{h}) =~ s/.*\@//;
createlog(file => "setup-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' started at $date\n");

# execute commands

my %sysctl;

install_pxe() if $mode{install};
upgrade_pxe() if $mode{upgrade};
get_version();
copy_scripts();
checkout_cvs() if $mode{install};
update_cvs() if $mode{upgrade} || $mode{cvs};
make_kernel() if $mode{kernel} || $mode{build};
make_build() if $mode{build};
diff_cvs("sys") if $mode{kernel} && !$mode{build};
diff_cvs() if $mode{build};
reboot() if $mode{kernel} || $mode{build};
get_version() if $mode{kernel} || $mode{build};
install_packages() if $mode{install} || $mode{upgrade};

# finish setup log

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");

exit;

# pxe install machine

sub install_pxe {
    logcmd('ssh', "$host\@$testmaster", "install", $release || ());
}

sub upgrade_pxe {
    logcmd('ssh', "$host\@$testmaster", "upgrade");
}

# reboot machine

sub reboot {
    logcmd('ssh', "$host\@$testmaster", "reboot");
}
# get version information

sub get_version {
    my @sshcmd = (('ssh', $opts{h}, 'sysctl'),
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
}

# copy scripts

sub copy_scripts {
    runcmd('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');
    chdir($bindir)
	or die "Chdir to '$bindir' failed: $!";
    my @copy = grep { -f $_ }
	("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list",
	"site.list");
    my @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$opts{h}:/root/regress");
    runcmd(@scpcmd);
    chdir($resultdir)
	or die "Chdir to '$resultdir' failed: $!";
}

# cvs checkout, update, diff

sub checkout_cvs {
    foreach (qw(src ports xenocara)) {
	logcmd('ssh', $opts{h},
	    "cd /usr && cvs -Rd /mount/openbsd/cvs co $_/Makefile")
    }
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/OPENBSD_${1}_${2}_BASE/;
    logcmd('ssh', $opts{h}, "cd /usr/src && cvs -R up -PdA $tag");
    logcmd('ssh', $opts{h}, "cd /usr/src && make obj");
}

sub update_cvs {
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/OPENBSD_${1}_${2}_BASE/;
    logcmd('ssh', $opts{h}, "cd /usr/src && cvs -qR up -PdA -C $tag");
    logcmd('ssh', $opts{h}, "cd /usr/src && make obj");
}

sub diff_cvs {
    my ($path) = @_;
    $path = $path ? " $path" : "";
    my @sshcmd = ('ssh', $opts{h}, 'cd /usr/src && cvs -qR diff -up'.$path);
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
    my $jflag = $ncpu > 1 ? "-j ".($ncpu+1) : "";
    logcmd('ssh', $opts{h}, "cd /usr/src/sys/$path && make config");
    logcmd('ssh', $opts{h}, "cd /usr/src/sys/$path && nice make $jflag");
    logcmd('ssh', $opts{h}, "cd /usr/src/sys/$path && make install");
}

sub make_build {
    my $ncpu = $sysctl{'hw.ncpu'};
    my $jflag = $ncpu > 1 ? "-j ".($ncpu+1) : "";
    logcmd('ssh', $opts{h}, "cd /usr/src && nice make $jflag build");
}

# install packages

sub install_packages {
    if (-f "$bindir/pkg-$host.list") {
	eval {
	    logcmd('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list",
		'-Ivx', $release ? () : '-Dsnap')
	};
	logmsg "WARNING: command failed\n" if $@;
    }
}

1;
