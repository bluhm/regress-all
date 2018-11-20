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
use Carp;
use Date::Parse;
use POSIX;

use parent 'Exporter';
our @EXPORT= qw(quirk_comments quirk_patches quirk_commands);

my %quirks = (
    '2018-04-05T03:32:39Z' => {
	comment => "remove PF_TRANS_ALTQ",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    # cvs has a bug and cannot check out vendor branches between commits
    '2018-04-07T10:05:05Z' => {
	comment => "fix cvs vendor branch checkout",
	updatecommands => [
	    "cvs -qR up -PdC -rOPENBSD_6_3_BASE gnu/usr.bin/cvs",
	],
	patches => { 'cvs-vendor' => <<'PATCH' },
Index: gnu/usr.bin/cvs/src/rcs.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/gnu/usr.bin/cvs/src/rcs.c,v
retrieving revision 1.26
diff -u -p -r1.26 rcs.c
--- gnu/usr.bin/cvs/src/rcs.c	28 May 2014 16:43:06 -0000	1.26
+++ gnu/usr.bin/cvs/src/rcs.c	7 Oct 2018 20:34:54 -0000
@@ -2824,6 +2824,7 @@ RCS_getdate (rcs, date, force_tag_match)
     char *cur_rev = NULL;
     char *retval = NULL;
     Node *p;
+    RCSVers *cur_vers;
     RCSVers *vers = NULL;
 
     /* make sure we have something to look at... */
@@ -2851,6 +2852,7 @@ RCS_getdate (rcs, date, force_tag_match)
 	    if (RCS_datecmp (vers->date, date) <= 0)
 	    {
 		cur_rev = vers->version;
+		cur_vers = vers;
 		break;
 	    }
 
@@ -2881,7 +2883,7 @@ RCS_getdate (rcs, date, force_tag_match)
 	if (p)
 	{
 	    vers = (RCSVers *) p->data;
-	    if (RCS_datecmp (vers->date, date) != 0)
+	    if (RCS_datecmp (vers->date, cur_vers->date) != 0)
 		return xstrdup ("1.1");
 	}
     }
PATCH
	buildcommands => [
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper install",
	],
    },
    '2018-04-07T10:05:06Z' => {
	comment => "update LLVM to 6.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-05-14T12:31:21Z' => {
	comment => "report CPU spinning time",
	updatedirs => [ "sys", "usr.bin/top", "usr.bin/systat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "usr.bin/top", "usr.bin/systat" ],
    },
    '2018-05-16T14:53:43Z' => {
	comment => "Add kern.witnesswatch sysctl",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/sysctl" ],
    },
    '2018-06-03T21:30:38Z' => {
	comment => "add ret protector options as no-ops",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-06-06T00:14:29Z' => {
	comment => "add RETGUARD to clang",
	updatedirs => [ "share/mk", "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [ "gnu/usr.bin/clang" ],
	builddirs => [ "share/mk", "gnu/usr.bin/clang" ],
    },
    '2018-07-10T09:28:27Z' => {
	comment => "pf generic packet delay",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2018-07-12T22:09:04Z' => {
	comment => "patch some garbage in GENERIC.MP",
	updatedirs => [ "sys/arch/amd64/conf/GENERIC.MP" ],
	patches => { 'sys-garbage' => <<'PATCH' },
Index: sys/arch/amd64/conf/GENERIC.MP
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/arch/amd64/conf/GENERIC.MP,v
retrieving revision 1.13
retrieving revision 1.14
diff -u -p -r1.13 -r1.14
--- sys/arch/amd64/conf/GENERIC.MP	12 Jul 2018 22:09:04 -0000	1.13
+++ sys/arch/amd64/conf/GENERIC.MP	13 Jul 2018 05:25:24 -0000	1.14
@@ -1,4 +1,4 @@
-0;331;0cwit#	$OpenBSD: GENERIC.MP,v 1.13 2018/07/12 22:09:04 deraadt Exp $
+#	$OpenBSD: GENERIC.MP,v 1.13 2018/07/12 22:09:04 deraadt Exp $
 
 include "arch/amd64/conf/GENERIC"
 
PATCH
    },
    '2018-07-12T22:09:04Z' => {
	comment => "zap some garbage in GENERIC.MP",
	updatedirs => [ "sys/arch/amd64/conf/GENERIC.MP" ],
    },
    '2018-07-26T13:20:53Z' => {
	comment => "infrastructure to install lld",
	updatedirs => [
	    "share/mk",
	    "gnu/usr.bin/clang/lld",
	    "gnu/usr.bin/binutils-2.17",
	],
	builddirs => [
	    "share/mk",
	    "gnu/usr.bin/clang/lld",
	],
	buildcommands => [
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper install",
	],
    },
);

sub quirks {
    my ($before, $after);
    if (@_) {
	$before = str2time($_[0])
	    or croak "Could not parse date '$_[0]'";
	$after = str2time($_[1])
	    or croak "Could not parse date '$_[1]'";
    }

    my %q;
    while (my($k, $v) = each %quirks) {
	my $commit = str2time($k)
	    or die "Invalid commit date '$k'";
	next if $before && $commit <= $before;
	next if $after && $commit > $after;
	$q{$commit} = $v;
    }
    return %q;
}

sub quirk_comments {
    my %q = quirks(@_);
    return map { $q{$_}{comment} } sort keys %q;
}

sub quirk_patches {
    my %q = quirks(@_);
    return map { %{$q{$_}{patches} || {}} } sort keys %q;
}

sub quirk_commands {
    my (undef, undef, $sysctl) = @_;
    my %q = quirks(@_);

    my @c;
    foreach my $commit (sort keys %q) {
	my $v = $q{$commit};
	push @c, "echo $v->{comment}";
	if ($v->{updatedirs}) {
	    my @dirs = @{$v->{updatedirs}};
	    my $tag = strftime("-D%FZ%T", gmtime($commit));
	    push @c, "cd /usr/src && cvs -qR up -PdC $tag @dirs";
	}
	foreach my $cmd (@{$v->{updatecommands} || []}) {
	    push @c, "cd /usr/src && $cmd";
	}
	foreach my $patch (sort keys %{$v->{patches} || {}}) {
	    my $file = "/root/perform/patches/$patch.diff";
	    push @c, "cd /usr/src && patch -p0 <$file";
	}
	foreach my $cmd (@{$v->{prebuildcommands} || []}) {
	    push @c, "cd /usr/src && $cmd";
	}
	foreach my $dir (@{$v->{cleandirs} || []}) {
	    push @c, "cd /usr/src && make -C $dir clean";
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
    }

    return @c;
}

1;
