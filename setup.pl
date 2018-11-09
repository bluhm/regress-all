#!/usr/bin/perl
# setup machine for regress test

# Copyright (c) 2016-2018 Alexander Bluhm <bluhm@genua.de>
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

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "setup-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' started at $date\n");

createhost($user, $host);

# execute commands

install_pxe($release) if $mode{install};
upgrade_pxe() if $mode{upgrade};
get_version();
copy_scripts();
checkout_cvs($release) if $mode{install};
update_cvs($release) if $mode{upgrade} || $mode{cvs};
make_kernel() if $mode{kernel} || $mode{build};
make_build() if $mode{build};
diff_cvs("sys") if $mode{kernel} && !$mode{build};
diff_cvs() if $mode{build};
reboot() if $mode{kernel} || $mode{build};
get_version() if $mode{kernel} || $mode{build};
install_packages($release) if $mode{install} || $mode{upgrade};

# finish setup log

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");

exit;

# copy scripts

sub copy_scripts {
    chdir($bindir)
	or die "Chdir to '$bindir' failed: $!";

    runcmd('ssh', "$user\@$host", 'mkdir', '-p', '/root/regress');
    my @copy = grep { -f $_ }
	("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list",
	"site.list");
    my @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$user\@$host:/root/regress");
    runcmd(@scpcmd);

    runcmd('ssh', "$user\@$host", 'mkdir', '-p', '/root/perform');
    @copy = grep { -f $_ }
	("perform.pl", "env-$host.sh", "pkg-$host.list");
    @scpcmd = ('scp');
    push @scpcmd, '-q' unless $opts{v};
    push @scpcmd, (@copy, "$user\@$host:/root/perform");
    runcmd(@scpcmd);

    chdir($resultdir)
	or die "Chdir to '$resultdir' failed: $!";

    if (my %patches = quirk_patches()) {
	my $patchdir = "$resultdir/patches";
	if (mkdir("$patchdir.tmp")) {
	    # only one setup process may fill the directory
	    while (my ($file, $content) = each %patches) {
		my $path = "$patchdir/$file.diff";
		open(my $fh, '>', $path)
		    or die "Open '$path' for writing failed: $!";
		print $fh $content
		    or die "Write content to '$path' failed: $!";
		close($fh)
		    or die "Close '$path' after writing failed: $!";
	    }
	    # setup.pl might run in parallel, make directory creation atomic
	    rename("$patchdir.tmp", $patchdir) || $!{EEXIST}
		or die "Rename '$patchdir.tmp' to '$patchdir' failed: $!";
	} else {
	    $!{EEXIST}
		or die "Mkdir '$patchdir.tmp' failed: $!";
	}
	foreach (1..10) {
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
    if (-f "$bindir/pkg-$host.list") {
	eval {
	    logcmd('ssh', "$user\@$host", 'pkg_add',
		'-l', "regress/pkg-$host.list",
		'-Ivx', $release ? () : '-Dsnap')
	};
	logmsg "WARNING: command failed\n" if $@;
    }
}
