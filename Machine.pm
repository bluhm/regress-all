# functions to manipulate remote test machine

# Copyright (c) 2018-2021 Alexander Bluhm <bluhm@genua.de>
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

package Machine;

use strict;
use warnings;
use Carp;
use Date::Parse;
use File::Copy;
use POSIX;

use Logcmd;

use parent 'Exporter';
our @EXPORT= qw(createhost reboot
    install_pxe upgrade_pxe get_bsdcons get_version
    checkout_cvs update_cvs diff_cvs clean_cvs patch_cvs update_ports
    make_kernel make_build
    align_kernel gap_kernel sort_kernel reorder_kernel
    get_bsdnm
);

# XXX explicit IP address in source code
our $testmaster = "10.0.1.1";

my ($user, $host, %sysctl);

sub createhost {
    ($user, $host) = @_;
}

# reboot machine

sub reboot {
    logcmd('ssh', "$host\@$testmaster", "reboot");
}

# pxe install machine

sub install_pxe {
    my ($release) = @_;
    logcmd('ssh', "$host\@$testmaster", "install",
	$release ? ("-r", $release) : ());
}

sub upgrade_pxe {
    logcmd('ssh', "$host\@$testmaster", "upgrade");
}

# console output since last OpenBSD kernel boot

sub get_bsdcons {
    logcmd({
	cmd => ['ssh', "$host\@$testmaster", "bsdcons"],
	outfile => "bsdcons-$host.txt.new",
    });
    rename("bsdcons-$host.txt.new", "bsdcons-$host.txt") or
	die "Rename 'bsdcons-$host.txt.new' to 'bsdcons-$host.txt' failed: $!";
}

# get version information

sub get_version {
    my @sshcmd = (('ssh', "$user\@$host", 'sysctl'),
	qw(kern.version hw.machine hw.ncpu));
    logmsg "Command '@sshcmd' started.\n";
    open(my $ctl, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $version, '>', "version-$host.txt.new")
	or die "Open 'version-$host.txt.new' for writing failed: $!";
    %sysctl = ();
    my $prevkey;
    local $_;
    while (defined($_ = <$ctl>)) {
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
    logmsg "Command '@sshcmd' finished.\n";
    close($version)
	or die "Close 'version-$host.txt.new' after writing failed: $!";
    rename("version-$host.txt.new", "version-$host.txt") or
	die "Rename 'version-$host.txt.new' to 'version-$host.txt' failed: $!";
    return %sysctl;
}

# cvs checkout, update, diff

sub checkout_cvs {
    my ($release) = @_;
    foreach (qw(src ports xenocara)) {
	logcmd('ssh', "$user\@$host",
	    "cd /usr && cvs -Rd /mount/openbsd/cvs co $_/Makefile")
    }
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/ -rOPENBSD_${1}_${2}_BASE/;
    logcmd('ssh', "$user\@$host", "cd /usr/src && cvs -R up -PdA$tag");
    logcmd('ssh', "$user\@$host", "cd /usr/src && make obj");
}

sub update_cvs {
    my ($release, $date, $path) = @_;
    cvs_update("src", @_);
    $path = $path ? " -C$path" : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && make$path obj");
}

sub cvs_update {
    my ($repo, $release, $date, $path) = @_;
    my $tag = $release || "";
    $tag =~ s/(\d+)\.(\d+)/ -rOPENBSD_${1}_${2}_BASE/;
    $tag = $date ? strftime(" -D%FZ%T", gmtime(str2time($date))) : "";
    $tag ||= "AC";  # for step checkouts per date preserve quirk patches
    $path = $path ? " $path" : "";
    logcmd('ssh', "$user\@$host", "cd /usr/$repo && cvs -qR up -Pd$tag$path");
}

sub diff_cvs {
    my ($path) = @_;
    $path = $path ? " $path" : "";
    my @sshcmd = ('ssh', "$user\@$host",
	"cd /usr/src && cvs -qR diff -up$path");
    logmsg "Command '@sshcmd' started.\n";
    open(my $cvs, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $diff, '>', "diff-$host.txt.new")
	or die "Open 'diff-$host.txt.new' for writing failed: $!";
    local $_;
    while (<$cvs>) {
	print $diff $_;
    }
    close($cvs) or do {
	die "Close pipe from '@sshcmd' failed: $!" if $!;
	# cvs diff returns 0 without and 1 with differences
	die "Command '@sshcmd' failed: $?" if $? != 0 && $? != (1<<8);
    };
    logmsg "Command '@sshcmd' finished.\n";
    close($diff)
	or die "Close 'diff-$host.txt.new' after writing failed: $!";
    rename("diff-$host.txt.new", "diff-$host.txt")
	or die "Rename 'diff-$host.txt.new' to 'diff-$host.txt' failed: $!";
}

sub clean_cvs {
    my ($path) = @_;
    $path = $path ? " $path" : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && cvs -qR up -C$path");
}

sub patch_cvs {
    my ($file, $path) = @_;
    $path = $path ? "/$path" : "";
    my @sshcmd = ('ssh', "$user\@$host", "cd /usr/src$path && patch -fF0");
    logmsg "Command '@sshcmd' started.\n";
    open(my $patch, '|-', @sshcmd)
	or die "Open pipe to '@sshcmd' failed: $!";
    copy($file, $patch)
	or die "Copy '$file' to '@sshcmd' failed: $!";
    close($patch) or die $! ?
	die "Close pipe to '@sshcmd' failed: $!" :
	die "Command '@sshcmd' failed: $?";
    logmsg "Command '@sshcmd' finished.\n";
}

sub update_ports {
    cvs_update("ports", @_);
    logcmd('ssh', "$user\@$host", "rm -rf /usr/ports/pobj");
    logcmd('ssh', "$user\@$host",
	"[ ! -f /usr/ports/infrastructure/mk/bsd.port.subdir.mk ] || ".
	"make -C /usr/ports fix-permissions");
}

# make /usr/src

sub make_kernel {
    my $version = $sysctl{'kern.version'};
    $version =~ m{:(?:/usr/src)?/sys/([\w./]+)$}m
	or die "No kernel path in version: $version";
    my $path = $1;
    my $ncpu = $sysctl{'hw.ncpu'};
    my $jflag = $ncpu > 1 ? " -j ".($ncpu+1) : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make config");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make clean")
	if loggrep(qr/you must run "make clean"/);
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && if [ -s CVS/Tag ]".
	"; then echo -n 'cvs : '; cat CVS/Tag; fi >obj/version");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && ".
	"time nice make$jflag bsd");
    logcmd('ssh', "$user\@$host", "cd /usr/src/sys/$path && make install");
    # disable kernel relinking, load after reboot may change perform result
    logcmd('ssh', "$user\@$host", "rm /var/db/kernel.SHA256");
}

sub make_build {
    my $ncpu = $sysctl{'hw.ncpu'};
    my $jflag = $ncpu > 1 ? " -j ".($ncpu+1) : "";
    logcmd('ssh', "$user\@$host", "cd /usr/src && time nice make$jflag build");
}

# make relink kernel

sub align_kernel {
    my ($src, $dst, $file);

    $src = "/usr/src/sys/arch/amd64/compile/GENERIC.MP/obj/Makefile";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/Makefile";
    $file = "/root/perform/patches/makefile-norandom.diff";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");

    $file = "/root/perform/patches/makefile-linkalign.diff";
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");
    $file = "/usr/share/relink/kernel/GENERIC.MP/ld.script";
    logcmd('ssh', "$user\@$host", "rm $file");
    $file = "/usr/share/relink/kernel/GENERIC.MP";
    logcmd('ssh', "$user\@$host", "make -C $file ld.script");

    $src = "/usr/src/sys/conf/makegap.sh";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/makegap.sh";
    $file = "/root/perform/patches/makegap-norandom.diff";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");
}

sub gap_kernel {
    my ($src, $dst, $file);

    $src = "/usr/src/sys/arch/amd64/compile/GENERIC.MP/obj/Makefile";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/Makefile";
    $file = "/root/perform/patches/makefile-norandom.diff";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");

    $src = "/usr/src/sys/conf/makegap.sh";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/makegap.sh";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
}

sub sort_kernel {
    my ($src, $dst, $file);

    $src = "/usr/src/sys/arch/amd64/compile/GENERIC.MP/obj/Makefile";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/Makefile";
    $file = "/root/perform/patches/makefile-norandom.diff";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");

    $src = "/usr/src/sys/conf/makegap.sh";
    $dst = "/usr/share/relink/kernel/GENERIC.MP/makegap.sh";
    $file = "/root/perform/patches/makegap-norandom.diff";
    logcmd('ssh', "$user\@$host", "cp $src $dst");
    logcmd('ssh', "$user\@$host", "patch -NuF0 -p0 $dst <$file");
}

sub reorder_kernel {
    my $cksum = "/var/db/kernel.SHA256";
    logcmd('ssh', "$user\@$host", "sha256 -h /var/db/kernel.SHA256 /bsd");
    logcmd('ssh', "$user\@$host", "cat /var/db/kernel.SHA256");
    logcmd('ssh', "$user\@$host", "/usr/libexec/reorder_kernel");
    logcmd('ssh', "$user\@$host", "cat /var/db/kernel.SHA256");
    logcmd('ssh', "$user\@$host", "rm /var/db/kernel.SHA256");
}

# get name list of kernel, addresses influence performance

sub get_bsdnm {
    my @sshcmd = ('ssh', "$user\@$host", 'nm', '/bsd');
    logmsg "Command '@sshcmd' started.\n";
    open(my $nm, '-|', @sshcmd)
	or die "Open pipe from '@sshcmd' failed: $!";
    open(my $fh, '>', "nm-bsd-$host.txt.new")
	or die "Open 'nm-bsd-$host.txt.new' for writing failed: $!";
    print $fh sort <$nm>;
    close($nm) or die $! ?
	"Close pipe from '@sshcmd' failed: $!" :
	"Command '@sshcmd' failed: $?";
    logmsg "Command '@sshcmd' finished.\n";
    close($fh)
	or die "Close 'nm-bsd-$host.txt.new' after writing failed: $!";
    rename("nm-bsd-$host.txt.new", "nm-bsd-$host.txt") or
	die "Rename 'nm-bsd-$host.txt.new' to 'nm-bsd-$host.txt' failed: $!";
}

1;
