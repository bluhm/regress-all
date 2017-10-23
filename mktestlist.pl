#!/usr/bin/perl
# print the Makefile leaves of the regress directory

# Copyright (c) 2016-2017 Alexander Bluhm <bluhm@genua.de>
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
use File::Find;

find(\&wanted, "/usr/src/regress");

my $prevdir;
sub wanted {
    return unless m{^Makefile$};
    if ($prevdir && $File::Find::dir !~ m{^\Q$prevdir\E/}) {
	$prevdir =~ s{^/usr/src/regress/}{};
	print $prevdir, "\n";
    }
    $prevdir = $File::Find::dir;
}
$prevdir =~ s{^/usr/src/regress/}{};
print $prevdir, "\n" if $prevdir;
