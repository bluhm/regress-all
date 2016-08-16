# run commands and log their output into file

package Logcmd;

use strict;
use warnings;

use parent 'Exporter';
our @EXPORT= qw(createlog logmsg runcmd logcmd);
use subs qw(logmsg);

my ($fh, $file, $verbose);
sub createlog (%) {
    my %args = @_;
    $file = $args{file};
    open(my $fh, '>', $file)
	or die "Open '$file' for writing failed: $!";
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
	and die "Command '@cmd' failed: $?";
    logmsg "Command '@cmd' finished\n";
}

sub logcmd (@) {
    my @cmd = @_;
    logmsg "Command '@cmd' started\n";
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
	logmsg $_;
    }
    close($out) or die $! ?
	"Close pipe from '@cmd' failed: $!" :
	"Command '@cmd' failed: $?";
    logmsg "Command '@cmd' finished\n";
}

1;
