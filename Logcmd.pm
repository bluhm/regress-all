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

sub forkcmd (@) {
    my @cmd = @_;
    logmsg "Command '@cmd' started\n";
    defined(my $pid = fork())
	or croak "Fork '@cmd' failed: $!";
    if ($pid == 0) {
	$SIG{__DIE__} = 'DEFAULT';
	open(STDIN, '<', "/dev/null")
	    or carp "Redirect stdin to /dev/null failed: $!";
	setsid()
	    or carp "Setsid $$ failed: $!";
	{
	    no warnings 'exec';
	    exec(@cmd);
	    carp "Exec '@cmd' failed: $!";
	}
	_exit(126);
    }
    return $pid => [@cmd];
}

sub waitcmd (%) {
    my %pidcmds = @_;;
    while (keys %pidcmds) {
	(my $pid = wait) == -1
	    and die "Wait failed: $!";
	my @cmd = @{$pidcmds{$pid}};
	$? and croak "Command '@cmd' failed: $?";
	logmsg "Command '@cmd' finished\n";
    }
}

sub logcmd (@) {
    my (@cmd, $outfile);
    if (ref($_[0])) {
	my %args = %{$_[0]};
	@cmd = ref($args{cmd}) ? @{$args{cmd}} : $args{cmd};
	$outfile = $args{outfile};
    } else {
	@cmd = @_;
    }
    logmsg "Command '@cmd' started\n";
    open(my $fh, '>', $outfile)
	or croak "Open file '$outfile' for writing failed: $!"
	if $outfile;
    defined(my $pid = open(my $out, '-|'))
	or croak "Open pipe from '@cmd' failed: $!";
    if ($pid == 0) {
	$SIG{__DIE__} = 'DEFAULT';
	close($out);
	open(STDIN, '<', "/dev/null")
	    or carp "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or carp "Redirect stderr to stdout failed: $!";
	open(STDOUT, '>&', $fh)
	    or carp "Redirect stdout to file failed: $!"
	    if $outfile;
	setsid()
	    or carp "Setsid $$ failed: $!";
	{
	    no warnings 'exec';
	    exec(@cmd);
	    carp "Exec '@cmd' failed: $!";
	}
	_exit(126);
    }
    close($fh) if $outfile;
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
