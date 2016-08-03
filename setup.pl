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

sub cmd {
    my @cmd = @_;
    print $log "Command '@cmd' started\n";
    print "Command '@cmd' started\n" if $opts{v};
    system(@cmd)
	and die "Command '@cmd' failed: $?";
    print $log "Command '@cmd' finished\n";
    print "Command '@cmd' finished\n" if $opts{v};
}

sub logcmd {
    my @cmd = @_;
    print $log "Command '@cmd' started\n";
    print "Command '@cmd' started\n" if $opts{v};
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
	print $log $_;
	s/[^\s[:print:]]/_/g;
	print if $opts{v};
    }
    close($out) or die $! ?
	"Close pipe from '@cmd' failed: $!" :
	"Command '@cmd' failed: $?";
    print $log "Command '@cmd' finished\n";
    print "Command '@cmd' finished\n" if $opts{v};
}

# pxe install machine

logcmd('ssh', "$host\@10.0.1.1", 'setup');

# get version information

my @sshcmd = ('ssh', $opts{h}, 'sysctl', 'kern.version');
print $log "Command '@sshcmd' started\n";
print "Command '@sshcmd' started\n" if $opts{v};
open(my $sysctl, '-|', @sshcmd)
    or die "Open pipe from '@sshcmd' failed: $!";
open(my $version, '>', "version-$host.txt")
    or die "Open 'version-$host.txt' for writing failed: $!";
print $version (<$sysctl>);
close($sysctl) or die $! ?
    "Close pipe from '@sshcmd' failed: $!" :
    "Command '@sshcmd' failed: $?";
print $log "Command '@sshcmd' finished\n";
print "Command '@sshcmd' finished\n" if $opts{v};

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
    "cd /usr && cvs -R -d /mount/openbsd/cvs co src/regress");

# install packages

logcmd('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list", '-Ivx')
    if -f "pkg-$host.list";
