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

my %quirks = (
    '2018-04-05T03:32:39Z' => {
	comment => "remove PF_TRANS_ALTQ",
	updatedirs => [ "sys/net" ], 
	builddirs => [ "include" ],
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
	updatedirs => [ "share/mk",
	    "gnu/usr.bin/binutils-2.17", "gnu/usr.bin/clang/ldd" ],
	builddirs => [ "share/mk",
	    "gnu/usr.bin/binutils-2.17", "gnu/usr.bin/clang/ldd" ],
    },
);

1;
