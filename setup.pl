#!/usr/bin/perl
# setup machine for regress test

# Copyright (c) 2016-2020 Alexander Bluhm <bluhm@genua.de>
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
use Machine;
use Buildquirks;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:h:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] -h host [-r release] mode ...
    -d date	set date string and change to sub directory
    -h host	root\@openbsd-test-machine, login per ssh
    -r release	use release for install and cvs checkout, X.Y or current
    -v		verbose
    build	build system from source /usr/src
    commands	run commands needed for some tests
    cvs		clean cvs update /usr/src and make obj
    install	install from snapshot
    kernel	build kernel from source /usr/src/sys
    keep	only copy version and scripts
    ports	cvs update /usr/ports
    tools	build and install tools needed for some tests
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{d} || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};

my %allmodes;
@allmodes{qw(build commands cvs install kernel keep ports tools upgrade)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
my $release;
if ($opts{r} && $opts{r} ne "current") {
    die "Upgrade to release not supported" if $mode{upgrade};
    ($release = $opts{r}) =~ /^\d+\.\d+$/
	or die "Release '$release' must be major.minor format";
}

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results";
$resultdir .= "/$date" if $date;
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
my $bindir = "$regressdir/bin";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "setup-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' started at $date.\n");

createhost($user, $host);

# execute commands

install_pxe($release) if $mode{install} && !$mode{keep};
upgrade_pxe() if $mode{upgrade} && !$mode{keep};
get_version();
copy_scripts();
checkout_cvs($release) if $mode{install} || $mode{upgrade};
update_cvs($release) if $mode{cvs};
update_ports($release) if $mode{ports};
make_kernel() if $mode{kernel} || $mode{build};
make_build() if $mode{build};
diff_cvs("sys") if $mode{kernel} && !$mode{build};
diff_cvs() if $mode{build};
reboot() if $mode{kernel} || $mode{build};
get_version() if $mode{kernel} || $mode{build};
install_packages($release) if $mode{install} || $mode{upgrade};
build_tools() if $mode{install} || $mode{upgrade} || $mode{tools};
run_commands() if $mode{install} || $mode{upgrade} || $mode{commands} ||
    $mode{ports};
get_bsdcons();

# finish setup log

$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $date.\n");

exit;

# copy scripts

sub copy_scripts {
    chdir($bindir)
	or die "Change directory to '$bindir' failed: $!";

    my @mkdirs = map { "/root/$_" } qw(regress perform portstest);
    runcmd('ssh', "$user\@$host", 'mkdir', '-p', @mkdirs);

    my @copy = grep { -f $_ }
	("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list",
	"site.list");
    my @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$user\@$host:/root/regress");
    runcmd(@scpcmd);

    @copy = grep { -f $_ }
	("perform.pl", "makealign.sh", "env-$host.sh", "pkg-$host.list");
    @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$user\@$host:/root/perform");
    runcmd(@scpcmd);

    @copy = grep { -f $_ }
	("portstest.pl", "env-$host.sh", "pkg-$host.list", "ports.list");
    @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$user\@$host:/root/portstest");
    runcmd(@scpcmd);

    chdir($resultdir)
	or die "Change directory to '$resultdir' failed: $!";

    if (my %patches = quirk_patches()) {
	my $patchdir = "$resultdir/patches";
	if (mkdir("$patchdir.tmp")) {
	    # only one setup process may fill the directory
	    while (my ($file, $content) = each %patches) {
		my $path = "$patchdir.tmp/$file.diff";
		open(my $fh, '>', $path)
		    or die "Open '$path' for writing failed: $!";
		print $fh $content
		    or die "Write content to '$path' failed: $!";
		close($fh)
		    or die "Close '$path' after writing failed: $!";
	    }
	    # setup.pl might run in parallel, make directory creation atomic
	    rename("$patchdir.tmp", $patchdir) || $!{EEXIST} || $!{ENOTEMPTY}
		or die "Rename '$patchdir.tmp' to '$patchdir' failed: $!";
	} else {
	    $!{EEXIST}
		or die "Make directory '$patchdir.tmp' failed: $!";
	}
	foreach (1..60) {
	    last if -d $patchdir;
	    sleep 1;
	}
	-d $patchdir
	    or die "Directory '$patchdir' does not exist";
	@scpcmd = ('scp');
	push @scpcmd, '-q' unless $opts{v};
	push @scpcmd, ('-r', 'patches', "$user\@$host:/root/perform");
	runcmd(@scpcmd);
    }
}

# install packages

sub install_packages {
    my ($release) = @_;
    return unless -f "$bindir/pkg-$host.list";

    logeval {
	logcmd('ssh', "$user\@$host", 'pkg_add',
	    '-l', "regress/pkg-$host.list",
	    '-Ivx', $release ? () : '-Dsnap')
    };
}

# build and install addtitional tools

sub build_tools {
    return unless -f "$bindir/build-$host.list";

    open(my $fh, '<', "$bindir/build-$host.list")
	or die "Open '$bindir/build-$host.list' for reading failed: $!";
    chomp(my @tools = <$fh>);
    close($fh)
	or die "Close '$bindir/build-$host.list' after reading failed: $!";

    foreach my $build (@tools) {
	my @scpcmd = ('scp', '-r');
	push @scpcmd, '-q' unless $opts{v};
	push @scpcmd, ("$bindir/../$build", "$user\@$host:/root/");
	runcmd(@scpcmd);
    }
    foreach my $build (@tools) {
	logcmd('ssh', "$user\@$host", 'make', '-C', "/root/$build", 'all');
	logcmd('ssh', "$user\@$host", 'make', '-C', "/root/$build", 'install');
    }
}

# run addtitional commands

sub run_commands {
    return unless -f "$bindir/cmd-$host.list";

    open(my $fh, '<', "$bindir/cmd-$host.list")
	or die "Open '$bindir/cmd-$host.list' for reading failed: $!";
    chomp(my @commands = <$fh>);
    close($fh)
	or die "Close '$bindir/cmd-$host.list' after reading failed: $!";

    my $prev;
    foreach my $run (@commands) {
	# line continuations are concatenated with a single space
	if (defined($prev)) {
	    $run =~ s/^\s*/$prev /;
	    undef $prev;
	}
	# comment starts in first column
	next if $run =~ /^#/;
	# long lines can be split with backslash
	if ($run =~ s/\s*\\$//) {
		$prev = $run;
		next;
	}
	# like make, ignore error when command starts with -
	if ($run =~ s/^-//) {
	    logeval { logcmd('ssh', "$user\@$host", $run) };
	} else {
	    logcmd('ssh', "$user\@$host", $run);
	}
    }
}
