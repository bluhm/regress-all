# get build over incompatible source changes with minimal effort

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
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

package Buildquirks;

use strict;
use warnings;
use Date::Parse;
use POSIX;

use parent 'Exporter';
our @EXPORT= qw(
    initquirks
    quirk_commands
);

my %quirks = (
    '2018-04-05T03:32:39Z' => {
	comment => "remove PF_TRANS_ALTQ",
	updatedirs => [ "sys/net" ], 
	buildcommands => [
	    [qw( make -C /usr/src includes )],
	],
    },
    '2018-04-07T10:05:06Z' => {
	comment => "update LLVM to 6.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ], 
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-06-06T00:14:29Z' => {
	comment => "add RETGUARD to clang",
	updatedirs => [ "share/mk", "gnu/llvm", "gnu/usr.bin/clang" ], 
	builddirs => [ "share/mk", "gnu/usr.bin/clang" ],
    },
    '2018-07-26T13:20:53Z' => {
	comment => "infrastructure to install lld",
	updatedirs => [
	    "share/mk",
	    "gnu/usr.bin/clang/ldd",
	    "gnu/usr.bin/binutils-2.17",
	],
	builddirs => [
	    "share/mk",
	    "gnu/usr.bin/clang/ldd",
	],
	buildcommands => [
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper install",
	],
    },
);

my $sysctl;

sub initquirks {
    ($sysctl) = @_;
}

sub quirk_commands {
    my ($before, $after) = @_;

    my %q;
    while (my($k, $v) = each %quirks) {
	my $commit = str2time($k)
	    or die "Invalid commit date '$k'";
	$q{$commit} = $v if $commit > $before && $commit <= $after;
    }
    my @c;
    foreach my $commit (sort keys %q) {
	my $v = $q{$commit};
	push @c, "echo $v->{comment}";
	if ($v->{updatedirs}) {
	    my $dirs = @{$v->{updatedirs}};
	    my $cvsdate = strftime("%FT%TZ", gmtime($commit));
	    push @c, "cd /usr/src && cvs -qR up -PdAC -D$cvsdate $dirs";
	}
	foreach my $dir (@{$v->{builddirs} || []}) {
	    my $ncpu = $sysctl->{'hw.ncpu'};
	    push @c, "cd /usr/src && make -C $dir obj";
	    push @c, "cd /usr/src && nice make -C $dir -j $ncpu all";
	    push @c, "cd /usr/src && make -C $dir install";
	}
	foreach my $cmd (@{$v->{buildcommands} || []}) {
	    push @c, "cd /usr/src && $cmd";
	}
	if ($v->{buildkernel}) {
	    my $version = $sysctl->{'kern.version'};
	    $version =~ m{:/usr/src/sys/([\w./]+)$}m
		or die "No kernel path in version: $version";
	    my $path = $1;
	    my $ncpu = $sysctl->{'hw.ncpu'};
	    push @c, "cd /usr/src/sys/$path && make obj";
	    push @c, "cd /usr/src/sys/$path && make config";
	    push @c, "cd /usr/src/sys/$path && make clean";
	    push @c, "cd /usr/src/sys/$path && nice make -j ncpu";
	    push @c, "cd /usr/src/sys/$path && make install";
	}
    }

    return @c;
}

1;
