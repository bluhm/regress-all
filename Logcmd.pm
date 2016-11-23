# run commands and log their output into file

package Logcmd;

use strict;
use warnings;
use Carp;
use POSIX;

use parent 'Exporter';
our @EXPORT= qw(createlog logmsg runcmd logcmd);
use subs qw(logmsg);

my ($fh, $file, $verbose);
sub createlog (%) {
    my %args = @_;
    $file = $args{file};
    open($fh, '>', $file)
	or croak "Open '$file' for writing failed: $!";
    $fh->autoflush();
    $verbose = $args{verbose};
    $| = 1 if $verbose;

    $SIG{__DIE__} = sub {
	print $fh @_;
	die @_;
    };
}

sub logmsg (@) {
    print $fh @_;
    print @_ if $verbose;
}

sub runcmd (@) {
    my @cmd = @_;
    logmsg "Command '@cmd' started\n";
    system(@cmd)
	and croak "Command '@cmd' failed: $?";
    logmsg "Command '@cmd' finished\n";
}

sub logcmd (@) {
    my @cmd = @_;
    logmsg "Command '@cmd' started\n";
    defined(my $pid = open(my $out, '-|'))
	or croak "Open pipe from '@cmd' failed: $!";
    if ($pid == 0) {
	$SIG{__DIE__} = 'DEFAULT';
	close($out);
	open(STDIN, '<', "/dev/null")
	    or carp "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or carp "Redirect stderr to stdout failed: $!";
	setsid()
	    or carp "Setsid $$ failed: $!";
	{
	    no warnings 'exec';
	    exec(@cmd);
	    carp "Exec '@cmd' failed: $!";
	}
	_exit(126);
    }
    local $_;
    while (<$out>) {
	s/[^\s[:print:]]/_/g;
	logmsg $_;
    }
    close($out) or croak $! ?
	"Close pipe from '@cmd' failed: $!" :
	"Command '@cmd' failed: $?";
    logmsg "Command '@cmd' finished\n";
}

1;
