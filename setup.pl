#!/usr/bin/perl
# setup machine for regress test

use strict;
use warnings;
use Cwd;
use File::Basename;
use Getopt::Std;
use POSIX;

my %opts;
getopts('d:h:v', \%opts) or do {
    print STDERR "usage: $0 [-v] [-d date] -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
$dir .= "/$date" if $date;
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;

my $setuplog = "setup-$host.log";
open(my $log, '>', $setuplog)
    or die "Open '$setuplog' for writing failed: $!";
$log->autoflush();
$| = 1;

$SIG{__DIE__} = sub {
    print $log @_;
    die @_;
};

use subs 'log';  # do not use CORE::log natural logarithm
sub log {
    print $log @_;
    print @_ if $opts{v};
}

sub cmd {
    my @cmd = @_;
    log "Command '@cmd' started\n";
    system(@cmd)
	and die "Command '@cmd' failed: $?";
    log "Command '@cmd' finished\n";
}

sub logcmd {
    my @cmd = @_;
    log "Command '@cmd' started\n";
    defined(my $pid = open(my $out, '-|'))
	or die "Open pipe from '@cmd' failed: $!";
    if ($pid == 0) {
	close($out);
	open(STDIN, '<', "/dev/null")
	    or warn "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or warn "Redirect stderr to stdout failed: $!";
	setsid()
	    or warn "Setsid $$ failed: $!";
	exec(@cmd);
	warn "Exec '@cmd' failed: $!";
	_exit(126);
    }
    while (<$out>) {
	s/[^\s[:print:]]/_/g;
	log $_;
    }
    close($out) or die $! ?
	"Close pipe from '@cmd' failed: $!" :
	"Command '@cmd' failed: $?";
    log "Command '@cmd' finished\n";
}

# pxe install machine

logcmd('ssh', "$host\@10.0.1.1", 'setup');

# get version information

my @sshcmd = ('ssh', $opts{h}, 'sysctl', 'kern.version');
log "Command '@sshcmd' started\n";
open(my $sysctl, '-|', @sshcmd)
    or die "Open pipe from '@sshcmd' failed: $!";
open(my $version, '>', "version-$host.txt")
    or die "Open 'version-$host.txt' for writing failed: $!";
print $version (<$sysctl>);
close($sysctl) or die $! ?
    "Close pipe from '@sshcmd' failed: $!" :
    "Command '@sshcmd' failed: $?";
log "Command '@sshcmd' finished\n";

# copy scripts

cmd('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');

$dir = "$regressdir/bin";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my @copy = grep { -f $_ }
    ("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list");
my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, (@copy, "$opts{h}:/root/regress");
cmd(@scpcmd);

# cvs checkout

logcmd('ssh', $opts{h},
    "cd /usr && cvs -R -d /mount/openbsd/cvs co src");

# install packages

logcmd('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list", '-Ivx')
    if -f "pkg-$host.list";
