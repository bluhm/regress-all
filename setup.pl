#!/usr/bin/perl
# setup machine for regress test

use strict;
use warnings;
use Cwd;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;

# XXX explicit IP address in source code
my $testmaster="10.0.1.4";

my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:h:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] -h host [mode ...]
    -v		verbose
    -d date	set date string and change to sub directory
    -h host	root\@openbsd-test-machine, login per ssh
    build	build system from source /usr/src
    cvs		cvs update /usr/src and make obj
    install	install from snapshot (default)
    kernel	build kernel from source /usr/src/sys
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};

my %allmodes;
@allmodes{qw(build cvs install kernel upgrade)} = ();
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV ? @ARGV : "install";
foreach (qw(install upgrade)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
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

# create new summary with setup log

runcmd("$regressdir/bin/setup-html.pl");

# execute commands

my %sysctl;

install_pxe() if $mode{install};
upgrade_pxe() if $mode{upgrade};
get_version();
copy_scripts();
checkout_cvs() if $mode{install};
update_cvs() if $mode{upgrade} || $mode{cvs};
make_kernel() if $mode{kernel};
make_build() if $mode{build};
diff_cvs("sys") if $mode{kernel};
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
    logcmd('ssh', "$host\@$testmaster", "install");
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
    while (defined(local $_ = <$ctl>)) {
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
    logcmd('ssh', $opts{h}, "cd /usr/src && cvs -R up -PdA");
    logcmd('ssh', $opts{h}, "cd /usr/src && make obj");
}

sub update_cvs {
    logcmd('ssh', $opts{h}, "cd /usr/src && cvs -qR up -PdA");
    logcmd('ssh', $opts{h}, "cd /usr/src && make obj");
}

sub diff_cvs {
    my ($path) = @_;
    $path = " $path" if $path;
    my @sshcmd = ('ssh', $opts{h}, 'cd /usr/src && cvs -qR diff -up'.$path);
    logmsg "Command '@sshcmd' started\n";
    open(my $cvs, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $diff, '>', "diff-$host.txt")
	or die "Open 'diff-$host.txt' for writing failed: $!";
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
		'-Ivx', '-Dsnap')
	};
	logmsg "WARNING: command failed\n" if $@;
    }
}

1;
