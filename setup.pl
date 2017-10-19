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

my %opts;
getopts('d:h:vbciku', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] -h host [mode ...]
    -v		verbose
    -d date	set date string and change to sub directory
    -h host	root\@openbsd-test-machine, login per ssh
    build	build system from source /usr/src
    cvs		cvs update /usr/src and make obj
    install	install from snapshot (default)
    sys		build kernel from source /usr/src/sys
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};

my %allmodes;
@allmodes{qw(build cvs install sys upgrade)} = ();
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV ? @ARGV : "install";
foreach (qw(install upgrade)) {
    die "Mode be used solely: $_" if $mode{$_} && keys %mode != 1;
}

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
$dir .= "/$date" if $date;
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;
createlog(file => "setup-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("script $0 started at $date\n");

# create new summary with setup log

runcmd("$regressdir/bin/setup-html.pl");

# execute commands

install_pxe();
get_version();
copy_scripts();
checkout_cvs();
install_packages();

# finish setup log

$date = strftime("%FT%TZ", gmtime);
logmsg("script $0 finished at $date\n");

exit;

# pxe install machine

sub install_pxe {
    # XXX explicit IP address in source code
    logcmd('ssh', "$host\@10.0.1.4", "install");
}

# get version information

sub get_version {
    my @sshcmd = ('ssh', $opts{h}, 'sysctl', 'kern.version', 'hw.machine');
    logmsg "Command '@sshcmd' started\n";
    open(my $sysctl, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $version, '>', "version-$host.txt")
	or die "Open 'version-$host.txt' for writing failed: $!";
    print $version (<$sysctl>);
    close($sysctl) or die $! ?
	"Close pipe from '@sshcmd' failed: $!" :
	"Command '@sshcmd' failed: $?";
    logmsg "Command '@sshcmd' finished\n";
}

# copy scripts

sub copy_scripts {
    runcmd('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');
    $dir = "$regressdir/bin";
    chdir($dir)
	or die "Chdir to '$dir' failed: $!";
    my @copy = grep { -f $_ }
	("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list",
	"site.list");
    my @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$opts{h}:/root/regress");
    runcmd(@scpcmd);
}

# cvs checkout

sub checkout_cvs {
    foreach (qw(src ports xenocara)) {
	logcmd('ssh', $opts{h},
	    "cd /usr && cvs -Rd /mount/openbsd/cvs co $_/Makefile")
    }
    logcmd('ssh', $opts{h}, "cd /usr/src && cvs -R up -PdA");
    logcmd('ssh', $opts{h}, "cd /usr/src && make obj");
}

# install packages

sub install_packages {
    if (-f "pkg-$host.list") {
	eval {
	    logcmd('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list",
		'-Ivx', '-Dsnap')
	};
	logmsg "WARNING: command failed\n" if $@;
    }
}

1;
