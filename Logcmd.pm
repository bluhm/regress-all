# run commands and log their output into file

# Copyright (c) 2016-2024 Alexander Bluhm <bluhm@genua.de>
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

package Logcmd;

use strict;
use warnings;
use Carp;
use File::Copy;
use POSIX;

use parent 'Exporter';
our @EXPORT= qw(createlog relogdie logmsg logeval runcmd forkcmd waitcmd logcmd
    loggrep);
use subs qw(logmsg);

my ($fh, $file, $verbose, @diemsg);
sub createlog {
    my %args = @_;
    $file = $args{file};
    open($fh, '>', $file)
	or croak "Open '$file' for writing failed: $!"
	if $file;
    $fh->autoflush() if $fh;
    $verbose = $args{verbose};
    $| = 1 if $verbose;

    $SIG{__DIE__} = sub {
	print $fh @_ if $fh;
	@diemsg = @_;
	die @_;
    };
}

sub relogdie {
    return unless @diemsg;
    print $fh @diemsg if $fh;
    print @diemsg if $verbose;
}

sub logmsg {
    print $fh @_ if $fh;
    print @_ if $verbose;
}

sub logeval(&) {
    my $code = shift;
    local $SIG{__DIE__};
    eval { &$code };
    logmsg "Warning: $@" if $@;
}

sub runcmd {
    my @cmd = @_;
    logmsg "Command '@cmd' started.\n";
    system(@cmd)
	and croak "Command '@cmd' failed: $?";
    logmsg "Command '@cmd' finished.\n";
}

sub forkcmd {
    my @cmd = @_;
    logmsg "Command '@cmd' started.\n";
    defined(my $pid = fork())
	or croak "Fork '@cmd' failed: $!";
    if ($pid == 0) {
	undef $SIG{__DIE__};
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
    return ($pid => [@cmd]);
}

my %waitstatus;
sub waitcmd {
    my %pidcmds = @_;
    my $total = keys %pidcmds;
    my $failed = 0;
    while (my $pid = each %waitstatus) {
	my $cmd = delete $pidcmds{$pid}
	    or next;
	# someone else has waited for our process
	my $status = delete $waitstatus{$pid};
	my @cmd = @$cmd;
	if ($status) {
	    logeval { croak "Command '@cmd' failed: $status" };
	    $failed++;
	} else {
	    logmsg "Command '@cmd' finished.\n";
	}
    }
    while (keys %pidcmds) {
	(my $pid = wait()) == -1
	    and croak "Wait failed: $!";
	my $status = $?;
	my $cmd = delete $pidcmds{$pid};
	unless ($cmd) {
	    # we have waited for someone else's process
	    $waitstatus{$pid} = $status;
	    next;
	}
	my @cmd = @$cmd;
	if ($status) {
	    logeval { croak "Command '@cmd' failed: $status" };
	    $failed++;
	} else {
	    logmsg "Command '@cmd' finished.\n";
	}
    }
    $failed and croak "Commands $failed out of $total failed";
}

sub logcmd {
    my (@cmd, $infile, $outfile);
    if (ref($_[0])) {
	my %args = %{$_[0]};
	@cmd = ref($args{cmd}) ? @{$args{cmd}} : $args{cmd};
	$infile = $args{infile};
	$outfile = $args{outfile};
    } else {
	@cmd = @_;
    }
    logmsg "Command '@cmd' started.\n";
    open(my $fh, '>', $outfile)
	or croak "Open file '$outfile' for writing failed: $!"
	if $outfile;
    logmsg "Writing output to '$outfile'.\n" if $outfile;
    defined(my $outpid = open(my $out, '-|'))
	or croak "Open pipe from '@cmd' failed: $!";
    if ($outpid == 0) {
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
	if ($infile) {
	    defined(my $inpid = open(my $in, '|-'))
		or croak "Open pipe to '@cmd' failed: $!";
	    if ($inpid == 0) {
		close($in);
		{
		    no warnings 'exec';
		    exec(@cmd);
		    carp "Exec '@cmd' failed: $!";
		}
		_exit(126);
	    }
	    copy($infile, $in)
		or die "Copy '$infile' to '@cmd' failed: $!";
	    close($in) or croak $! ?
		"Close pipe to '@cmd' failed: $!" :
		"Command '@cmd' failed: $?";
	    _exit(0);
	} else {
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
    logmsg "Command '@cmd' finished.\n";
}

sub loggrep {
    my ($regex) = @_;
    open(my $fh, '<', $file)
	or croak "Open '$file' for reading failed: $!";
    my @match = grep { /$regex/ } <$fh>;
    close($fh);
    return wantarray ? @match : $match[0];
}

1;
