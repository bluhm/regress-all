# get build over incompatible source changes with minimal effort

# Copyright (c) 2018-2024 Alexander Bluhm <bluhm@genua.de>
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
our @EXPORT= qw(quirks quirk_patches quirk_commands quirk_releases
    quirk_index2letters);

#### Quirks ####

my %quirks = (
# OpenBSD 6.2, newvers 2017-10-04Z
    '2017-10-04T03:27:49Z' => {
	comment => "OpenBSD/amd64 6.2 release",
	release => '6.2',
    },
    # cvs has a bug and cannot check out vendor branches between commits
    '2017-10-04T21:45:15Z' => {
	comment => "fix cvs vendor branch checkout",
	updatecommands => [
	    "cvs -qR up -PdC -rOPENBSD_6_2_BASE gnu/usr.bin/cvs",
	],
	patches => { 'cvs-vendor' => patch_cvs_vendor() },
	buildcommands => [
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper install",
	],
    },
    '2017-10-04T21:45:16Z' => {
	comment => "clang update LLVM to 5.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2017-11-13T11:30:11Z' => {
	comment => "pfctl pf packet rate matching",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2017-11-28T16:05:47Z' => {
	comment => "pfctl pf divert type",
	updatedirs => [ "sys", "sbin/pfctl" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2017-12-11T05:27:40Z' => {
	comment => "sysctl struct vfsconf",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/sysctl" ],
    },
    '2017-12-25T12:09:20Z' => {
	comment => "clang update LLVM to 5.0.1",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2017-11-16T18:12:27Z' => {
	comment => "move kernel source file dwiic.c",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2018-02-06T23:44:48Z' => {
	comment => "pfctl pf syncookies",
	updatedirs => [ "sys", "sbin/pfctl" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
# OpenBSD 6.3, 2018-03-24Z, newvers 2018-03-27Z
    '2018-03-24T20:27:40Z' => {
	comment => "OpenBSD/amd64 6.3 release",
	release => '6.3',
    },
    '2018-04-05T03:32:39Z' => {
	comment => "pfctl remove PF_TRANS_ALTQ",
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
	patches => { 'cvs-vendor' => patch_cvs_vendor() },
	buildcommands => [
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper install",
	],
    },
    '2018-04-07T10:05:06Z' => {
	comment => "clang update LLVM to 6.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-04-27T15:19:32Z' => {
	comment => "retpoline for kernel",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2018-05-02T13:20:12Z' => {
	comment => "revert remaining puc commit for com",
	updatedirs => [ "sys" ],
	patches => { 'sys-puc' => patch_sys_puc() },
    },
    '2018-05-14T12:31:21Z' => {
	comment => "top systat report CPU spinning time",
	updatedirs => [ "sys", "usr.bin/top", "usr.bin/systat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "usr.bin/top", "usr.bin/systat" ],
    },
    '2018-05-16T14:53:43Z' => {
	comment => "sysctl add kern.witnesswatch",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/sysctl" ],
    },
    '2018-06-03T21:30:38Z' => {
	comment => "clang add ret protector options as no-ops",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-06-06T00:14:29Z' => {
	comment => "clang add retguard",
	updatedirs => [ "share/mk", "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "share/mk", "gnu/usr.bin/clang" ],
    },
    '2018-07-10T09:28:27Z' => {
	comment => "pfctl pf generic packet delay",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2018-07-12T22:09:04Z' => {
	comment => "patch some garbage in GENERIC.MP",
	updatedirs => [ "sys/arch/amd64/conf/GENERIC.MP" ],
	patches => { 'sys-garbage' => patch_sys_garbage() },
    },
    '2018-07-13T05:25:24Z' => {
	comment => "zap some garbage in GENERIC.MP",
	updatedirs => [ "sys/arch/amd64/conf/GENERIC.MP" ],
    },
    '2018-07-26T13:20:53Z' => {
	comment => "binutils infrastructure to install lld",
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
    '2018-08-12T17:07:00Z' => {
	comment => "clang refactor retguard",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
# OpenBSD 6.4, 2018-10-11Z, newvers 2018-09-29Z
    '2018-10-11T19:37:31Z' => {
	comment => "OpenBSD/amd64 6.4 release",
	release => '6.4',
    },
    '2018-10-16T18:20:58Z' => {
	comment => "prepare kernel for lld linker",
	updatedirs => [ "sys" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2018-10-22T15:18:50Z' => {
	comment => "cvs vendor branch checkout",
	updatedirs => [ "gnu/usr.bin/cvs" ],
	buildcommands => [
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/cvs -f Makefile.bsd-wrapper install",
	],
    },
    '2018-10-22T19:31:30Z' => {
	comment => "use lld as default linker",
	updatedirs => [ "share/mk" ],
	builddirs => [ "share/mk" ],
    },
    '2018-10-24T21:19:03Z' => {
	comment => "clang with final lld fixes",
	updatedirs => [ "gnu/llvm" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2018-12-30T23:08:05Z' => {
	comment => "clang turns on retpoline by default",
	updatedirs => [ "sys", "gnu/llvm" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2019-01-12T23:36:35Z' => {
	comment => "clang builds itself without retpoline",
	updatedirs => [ "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2019-01-27T17:29:36Z' => {
	comment => "clang update LLVM to 7.0.1",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2019-01-30T03:08:12Z' => {
	comment => "clang implement save function arguments",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	patches => { 'llvm-save-func' => patch_llvm_save_func() },
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2019-02-03T10:58:51Z' => {
	comment => "save function arguments for ddb traces",
	updatedirs => [ "sys" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2019-02-18T13:11:44Z' => {
	comment => "pfctl pf len ioctl get states",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2019-03-01T16:46:11Z' => {
	comment => "binutils for libLLVM",
	updatedirs => [ "gnu/usr.bin/binutils", "gnu/usr.bin/binutils-2.17" ],
	buildcommands => [
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper install",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper install",
	],
    },
    '2019-03-05T14:01:08Z' => {
	comment => "clang with libLLVM",
	updatedirs => [ "share/mk", "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "share/mk", "gnu/usr.bin/clang" ],
    },
    '2019-04-02T03:02:47Z' => {
	comment => "clang no stack protector if retguard",
	updatedirs => [ "share/mk", "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "share/mk", "gnu/usr.bin/clang" ],
    },
# OpenBSD 6.5, newvers 2019-04-13Z
    '2019-04-13T20:56:59Z' => {
	comment => "OpenBSD/amd64 6.5 release",
	release => '6.5',
    },
    '2019-05-08T23:53:40Z' => {
	comment => "add ucrcom to files",
	updatedirs => [ "sys" ],
	patches => { 'sys-ucrcom' => patch_sys_files_ucrcom() },
    },
    '2019-06-17T22:31:48Z' => {
	comment => "libcxx update libc++, libc++abi, libunwind to 8.0.0",
	updatedirs => [ "lib/libcxx", "lib/libcxxabi",  "lib/libunwind" ],
	cleandirs => [ "lib/libcxx", "lib/libcxxabi" ],
	builddirs => [ "lib/libcxx", "lib/libcxxabi" ],
    },
    '2019-06-23T17:18:50Z' => {
	comment => "sysctl kinfo_proc add p_pledge",
	updatedirs => [ "sys", "lib/libkvm", "bin/ps" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [
	    "lib/libkvm",
	    "bin/ps",
	    "usr.bin/pkill",
	    "usr.bin/systat",
	    "usr.bin/top",
	],
    },
    '2019-06-23T22:21:06Z' => {
	comment => "clang update LLVM to 8.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2019-06-25T14:08:57Z' => {
	comment => "sysctl kinfo_proc move p_pledge",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [
	    "lib/libkvm",
	    "bin/ps",
	    "usr.bin/pkill",
	    "usr.bin/systat",
	    "usr.bin/top",
	],
    },
    '2019-08-02T02:17:35Z' => {
	comment => "per-process itimers, missing part of commit",
	updatedirs => [ "sys" ],
	patches => { 'sys-time' => patch_sys_sys_time() },
    },
    '2019-08-28T22:39:09Z' => {
	comment => "uhci PCI ACPI attach fail",
	updatedirs => [ "sys" ],
	patches => { 'sys-uhci' => patch_sys_uhci_activate() },
    },
    '2019-09-01T16:40:03Z' => {
	comment => "clang update LLVM to 8.0.1",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
# OpenBSD 6.6, newvers 2019-10-12Z
    '2019-10-12T17:05:22Z' => {
	comment => "OpenBSD/amd64 6.6 release",
	release => '6.6',
    },
    '2019-11-03T20:16:01Z' => {
	comment => "sys_shmctl fix copyin",
	updatedirs => [ "sys" ],
	patches => { 'sys-shm' => patch_sys_shm_copyin() },
    },
    '2019-11-27T01:13:04Z' => {
	comment => "kernel provides msyscall as a noop",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make includes",
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    # Reboot to kernel with dummy syscall msyscall before ld.so quirk.
    '2019-11-29T06:34:46Z' => {
	comment => "ld.so uses msyscall to permit syscalls",
	updatedirs => [ "libexec/ld.so" ],
	builddirs => [ "libexec/ld.so" ],
    },
# OpenBSD 6.7, newvers 2020-05-07Z
    '2020-05-07T17:20:22Z' => {
	comment => "OpenBSD/amd64 6.7 release",
	release => '6.7',
    },
    '2020-06-08T04:48:12Z' => {
	comment => "update drm moves kernel source files",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2020-07-06T13:33:09Z' => {
	comment => "kernel provides timecounting in userland",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    '2020-07-08T09:17:48Z' => {
	comment => "libc uses timecounting in userland",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "lib/libc" ],
    },
    '2020-07-17T06:33:07Z' => {
	comment => "include toeplitz.h in ixgbe.h",
	updatedirs => [ "sys" ],
	patches => { 'sys-ix-toeplitz' => patch_sys_ix_toeplitz() },
    },
    '2020-07-17T07:40:35Z' => {
	comment => "include toeplitz.h in ixgbe.h and backout in if_ix.c",
	updatedirs => [ "sys" ],
	patches => {
	    'sys-ix-toeplitz' => patch_sys_ix_toeplitz(),
	    'sys-ix-toeplitz-bad' => patch_sys_ix_toeplitz_bad(),
	},
    },
    '2020-07-17T07:49:49Z' => {
	comment => "backout bad include of toeplitz.h in if_ix.c",
	updatedirs => [ "sys" ],
	patches => { 'sys-ix-toeplitz-bad' => patch_sys_ix_toeplitz_bad() },
    },
    '2020-07-23T14:53:48Z' => {
	comment => "binutils bfd fixes strip after clang 10",
	updatedirs => [ "gnu/usr.bin/binutils-2.17" ],
	buildcommands => [
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper install",
	],
    },
    '2020-08-03T15:29:25Z' => {
	comment => "clang update LLVM to 10.0.0",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2020-08-09T15:56:55Z' => {
	comment => "clang update LLVM to 10.0.1",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
    '2020-09-12T07:47:27Z' => {
	comment => "move asmc.c kernel source file",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2020-10-01T14:02:08Z' => {
	comment => "pfctl routing domain check",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
	patches => { 'sys-pf-rdomain' => patch_sys_pf_rdomain() },
    },
# OpenBSD 6.8, 2020-09-27Z, newvers 2020-09-30Z
    '2020-10-05T00:22:38Z' => {
	comment => "OpenBSD/amd64 6.8 release",
	release => '6.8',
    },
    '2021-02-08T11:20:04Z' => {
	comment => "softraid_raid1c.c was not added in commit",
	updatecommands => [
	    "cvs -qR up -p -r1.1 sys/dev/softraid_raid1c.c ".
		">sys/dev/softraid_raid1c.c",
	],
    },
    '2021-02-08T11:21:53Z' => {
	comment => "replace softraid_raid1c.c copy with commit",
	updatecommands => [
	    "rm -f sys/dev/softraid_raid1c.c",
	    "cvs -qR up -C -r1.1 sys/dev/softraid_raid1c.c",
	],
    },
# OpenBSD 6.9, newvers 2021-04-18Z
    '2021-04-19T16:48:56Z' => {
	comment => "OpenBSD/amd64 6.9 release",
	release => '6.9',
    },
    '2021-04-28T13:07:33Z' => {
	comment => "clang, libc++, and libc++abi update LLVM to 11.1.0",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
    },
    '2021-05-21T16:52:42Z' => {
	comment => "futex ABI change in libc and librthread",
	updatedirs => [ "lib/libc", "lib/librthread" ],
	builddirs => [ "lib/libc", "lib/librthread" ],
    },
    '2021-06-13T21:11:54Z' => {
	comment => "futex full syscall stub and save errno",
	cleandirs => [ "lib/libc" ],
	updatedirs => [ "lib/libc", "lib/librthread" ],
	builddirs => [ "lib/libc", "lib/librthread" ],
    },
    '2021-06-28T08:55:06Z' => {
	comment => "btrace includes userland in kstack",
	updatedirs => [ "usr.sbin/btrace" ],
	builddirs => [ "usr.sbin/btrace" ],
    },
    '2021-07-07T02:38:38Z' => {
	comment => "update drm moves kernel source files",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2021-09-01T13:37:14Z' => {
	comment => "clang lfence after ret in retpoline",
	updatedirs => [ "gnu/llvm", "gnu/usr.bin/clang" ],
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	builddirs => [ "gnu/usr.bin/clang" ],
    },
# OpenBSD 7.0, newvers 2021-09-22Z
    '2021-09-30T20:34:00Z' => {
	comment => "OpenBSD/amd64 7.0 release",
	release => '7.0',
    },
    '2021-10-21T22:59:08Z' => {
	comment => "remove dangling crypto noqueue, missing part of commit",
	updatedirs => [ "sys" ],
	patches => { 'sys-softraid-crypto' => patch_sys_softraid_crypto() },
    },
    '2021-11-23T10:30:08Z' => {
	comment => "install bsd.own.mk with ar variable",
	updatedirs => [ "share/mk" ],
	builddirs => [ "share/mk" ],
    },
    '2021-12-17T14:55:47Z' => {
	comment => "clang, libc++, and libc++abi update LLVM to 13.0.0",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
    },
    '2021-12-23T18:50:59Z' => {
	comment => "kernel removes padding from syscalls",
	updatedirs => [
	    "sys",
	    "lib/libc",
	    "libexec/ld.so",
	],
	prebuildcommands => [
	    "make includes",
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    '2022-01-14T06:53:17Z' => {
	comment => "update drm moves kernel source files",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2022-02-22T17:26:04Z' => {
	comment => "maxcomlen include",
	updatedirs => [ "sys", "sbin/sysctl", "usr.sbin/btrace" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/sysctl", "usr.sbin/btrace" ],
    },
    '2022-02-22T17:42:52Z' => {
	comment => "param include",
	updatedirs => [
	    "lib/libkvm",
	    "bin/ps",
	    "usr.bin/kdump",
	    "usr.bin/ktrace",
	    "usr.bin/systat",
	    "usr.bin/tmux",
	    "usr.bin/top",
	    "usr.bin/vmstat",
	    "usr.bin/w",
	    "usr.sbin/procmap",
	    "usr.sbin/pstat",
	    "usr.sbin/sa",
	    "usr.sbin/tcpdump",
	],
	builddirs => [
	    "lib/libkvm",
	    "bin/ps",
	    "usr.bin/kdump",
	    "usr.bin/ktrace",
	    "usr.bin/systat",
	    "usr.bin/tmux",
	    "usr.bin/top",
	    "usr.bin/vmstat",
	    "usr.bin/w",
	    "usr.sbin/procmap",
	    "usr.sbin/pstat",
	    "usr.sbin/sa",
	    "usr.sbin/tcpdump",
	],
    },
    '2022-03-23T14:36:01Z' => {
	comment => "revert scsi link commit, panic during boot",
	updatedirs => [ "sys" ],
	patches => { 'sys-scsi-link' => patch_sys_scsi_link() },
    },
# OpenBSD 7.1, newvers 2022-04-05Z
    '2022-04-12T00:10:09Z' => {
	comment => "OpenBSD/amd64 7.1 release",
	release => '7.1',
    },
    '2022-09-22T04:57:08Z' => {
	comment => "libc RDTSCP for tsc and usertc",
	updatedirs => [ "sys", "include", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "lib/libc" ],
    },
# OpenBSD 7.2, newvers 2022-09-27Z
    '2022-09-27T18:03:44Z' => {
	comment => "OpenBSD/amd64 7.2 release",
	release => '7.2',
    },
    '2022-10-07T15:00:12Z' => {
	comment => "kernel provides mimmutable system call",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make includes",
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    '2022-10-07T15:04:52Z' => {
	comment => "llvm and binutils create openbsd mutable section",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/binutils",
	    "gnu/usr.bin/binutils-2.17",
	],
	builddirs => [ "gnu/usr.bin/clang" ],
	buildcommands => [
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper obj",
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper all",
	    "make -C gnu/usr.bin/binutils -f Makefile.bsd-wrapper install",
	    "make -C gnu/usr.bin/binutils-2.17 -f Makefile.bsd-wrapper install",
	],
    },
    '2022-10-07T15:21:04Z' => {
	comment => "libc provides mimmutable stub",
	updatedirs => [ "lib/libc", "lib/librthread" ],
	builddirs => [ "lib/libc", "lib/librthread" ],
    },
    '2022-11-09T10:41:18Z' => {
	comment => "revert replace SRP with SMR in the if_idxmap",
	updatedirs => [ "sys" ],
	patches => { 'sys-if-srp-smr' => patch_sys_if_srp_smr() },
    },
    '2022-11-09T19:50:25Z' => {
	comment => "ld.so uses mimmutable",
	updatedirs => [ "libexec/ld.so" ],
	builddirs => [ "libexec/ld.so" ],
    },
    '2022-11-09T22:15:50Z' => {
	comment => "update fixed revert replace SRP with SMR",
	updatedirs => [ "sys" ],
    },
    '2022-11-09T22:25:08Z' => {
	comment => "fix build in kern pledge",
	updatedirs => [ "sys" ],
	patches => { 'sys-pledge-nodelay' => patch_sys_pledge_nodelay() },
    },
    '2022-11-09T23:00:00Z' => {
	comment => "simplify expiration of once rules",
	updatedirs => [ "sys", "sbin/pfctl" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
	patches => { 'sys-pledge-nodelay' => patch_sys_pledge_nodelay() },
    },
    '2022-11-10T00:14:11Z' => {
	comment => "update fixed kern pledge",
	updatedirs => [ "sys" ],
    },
    '2022-11-11T10:55:48Z' => {
	comment => "remove struct pf_state from pfvar.h",
	updatedirs => [ "sys", "sbin/pfctl" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
    '2022-11-11T12:29:32Z' => {
	comment => "fix build in pfvar priv header",
	updatedirs => [ "sys" ],
	patches => { 'sys-pfvar-annotations' => patch_sys_pfvar_annotations() },
    },
    '2022-11-11T12:36:05Z' => {
	comment => "update fixed pfvar priv header",
	updatedirs => [ "sys" ],
    },
    '2022-11-11T16:12:08Z' => {
	comment => "pf purge without netlock, fix hang in ixgbe ioctl",
	updatedirs => [ "sys" ],
	patches => { 'sys-pf-purge' => patch_sys_pf_purge() },
    },
    '2022-11-25T03:45:39Z' => {
	comment => "update fixed pf purge without netlock",
	updatedirs => [ "sys" ],
    },
    '2022-11-25T18:03:53Z' => {
	comment => "backout pf purge without netlock",
	updatedirs => [ "sys" ],
	patches => { 'sys-pf-purge-backout' => patch_sys_pf_purge_backout() },
    },
    '2022-11-25T20:27:53Z' => {
	comment => "backout pf purge commit",
	updatedirs => [ "sys" ],
    },
    '2023-01-01T01:35:00Z' => {
	comment => "update drm moves kernel source files",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2023-02-07T17:58:43Z' => {
	comment => "change icmp fields of struct pf_rule in pfvar.h",
	updatedirs => [ "sys", "sbin/pfctl" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl" ],
    },
# OpenBSD 7.3, newvers 2023-03-25Z
    '2023-03-25T16:42:45' => {
	comment => "OpenBSD/amd64 7.3 release",
	release => '7.3',
    },
    '2023-03-25T15:22:06Z' => {
	comment => "libc malloc chunk sizes fine grained",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	cleandirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-04-01T18:47:51Z' => {
	comment => "libc malloc check chunks in delayed free list",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-04-05T06:25:38Z' => {
	comment => "libc malloc variation in location of junked bytes",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-04-16T19:46:17Z' => {
	comment => "libc malloc dump leak info using utrace",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-04-16T23:57:59Z' => {
	comment => "build gapdummy without cf-protection branch",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	patches => { 'sys-amd64-cfgap' => patch_sys_amd64_cfgap() },
    },
    '2023-04-26T06:52:45Z' => {
	comment => "sendsyslog declared in syslog.h",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
    },
    '2023-04-26T15:13:59Z' => {
	comment => "vmm kernel source files moved",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2023-04-27T23:16:18Z' => {
	comment => "use __size_t in sys/syslog.h",
	updatedirs => [ "sys" ],
	prebuildcommands => [ "make includes" ],
    },
    '2023-05-10T07:58:06Z' => {
	comment => "libc malloc mmap unlocked, away with unlock-lock dance",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-05-10T12:07:17Z' => {
	comment => "netstat TSO counter",
	updatedirs => [ "sys", "usr.bin/netstat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "usr.bin/netstat" ],
    },
    '2023-05-23T09:16:16Z' => {
	comment => "netstat LRO counter",
	updatedirs => [ "sys", "usr.bin/netstat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "usr.bin/netstat" ],
    },
    '2023-05-27T04:33:00Z' => {
	comment => "libc malloc remove interposition",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-06-04T06:58:33Z' => {
	comment => "libc malloc thorough write-after-free checks",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-06-30T06:24:58Z' => {
	comment => "libc malloc deeper callers for leak reports",
	updatedirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-07-31T04:01:07Z' => {
	comment => "kernel eIBRS disable retpoline",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
# OpenBSD 7.4, newvers 2023-10-04Z
    '2023-10-10T15:08:35Z' => {
	comment => "OpenBSD/amd64 7.4 release",
	release => '7.4',
    },
    '2023-10-25T20:05:43Z' => {
	comment => "patch fix unveil patchfile",
	updatedirs => [ "usr.bin/patch" ],
	builddirs => [ "usr.bin/patch" ],
    },
    '2023-10-26T17:59:16Z' => {
	comment => "libc malloc micro optimizations",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	cleandirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-11-12T14:41:41Z' => {
	comment => "login.conf bump datasize for clang",
	updatedirs => [ "etc/etc.amd64" ],
	commands => [ "cp /usr/src/etc/etc.amd64/login.conf /etc/" ],
    },
    '2023-11-20T10:11:03Z' => {
	comment => "clang, libc++, and libc++abi update LLVM to 16.0.6",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
	cleandirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
    },
    '2023-12-04T07:01:45Z' => {
	comment => "libc malloc backtrace",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	cleandirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-12-04T14:24:29Z' => {
	comment => "clang fixes after LLVM update",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	    "gnu/lib/libcxx",
	    "gnu/lib/libcxxabi",
	],
	cleandirs => [
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	],
    },
    '2023-12-07T14:00:16Z' => {
	comment => "kernel pinsyscalls stub",
	updatedirs => [
	    "sys",
	    "lib/libc",
	    "libexec/ld.so",
	],
	prebuildcommands => [
	    "make includes",
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	    "make -C sys/arch/amd64/compile/GENERIC.MP clean",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    '2023-12-19T06:59:28Z' => {
	comment => "libc malloc bytes cleanup",
	updatedirs => [ "sys", "lib/libc" ],
	prebuildcommands => [ "make includes" ],
	cleandirs => [ "lib/libc" ],
	builddirs => [ "lib/libc" ],
    },
    '2023-12-22T23:01:50Z' => {
	comment => "backout always allocate if counters",
	updatedirs => [ "sys" ],
	patches => {
	    'sys-if-counters-backout' => patch_sys_if_counters_backout()
	},
    },
    '2023-12-23T10:52:55Z' => {
	comment => "backout if counters commit",
	updatedirs => [ "sys" ],
    },
    '2024-01-16T23:38:14Z' => {
	comment => "update drm moves kernel source files",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2024-02-03T18:51:59Z' => {
	comment => "softdep kernel source files removed",
	cleandirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
    },
    '2024-02-05T23:16:39Z' => {
	comment => "netstat route cache counter",
	updatedirs => [ "sys", "usr.bin/netstat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "usr.bin/netstat" ],
    },
    '2024-02-19T14:08:58Z' => {
	comment => "clang disable retpoline",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	],
	cleandirs => [
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	],
    },
# OpenBSD 7.5, newvers 2024-03-12Z
    '2024-03-20T21:54:47Z' => {
	comment => "OpenBSD/amd64 7.5 release",
	release => '7.5',
    },
    '2024-03-29T06:47:05Z' => {
	comment => "kernel removes msyscall check",
	updatedirs => [ "sys" ],
	prebuildcommands => [
	    "make -C sys/arch/amd64/compile/GENERIC.MP config",
	],
	builddirs => [ "sys/arch/amd64/compile/GENERIC.MP" ],
	commands => [ "reboot" ],
    },
    '2024-04-05T13:51:47Z' => {
	comment => "ld.so removes msyscall call",
	updatedirs => [ "libexec/ld.so" ],
	builddirs => [ "libexec/ld.so" ],
    },
    '2024-04-22T13:30:22Z' => {
	comment => "pfctl fragment reassembly counters",
	updatedirs => [ "sys", "sbin/pfctl", "usr.bin/systat" ],
	prebuildcommands => [ "make includes" ],
	builddirs => [ "sbin/pfctl", "usr.bin/systat", "usr.sbin/relayd" ],
    },
    '2024-06-02T15:42:19Z' => {
	comment => "clang add -fret-clean option",
	updatedirs => [
	    "gnu/llvm",
	    "gnu/usr.bin/clang",
	],
	cleandirs => [
	    "sys/arch/amd64/compile/GENERIC.MP",
	],
	builddirs => [
	    "gnu/usr.bin/clang",
	],
    },
);

#### Patches ####

# modify linker script to align all object sections at page boundary
sub patch_makefile_linkalign {
	return <<'PATCH';
--- /usr/src/sys/arch/amd64/compile/GENERIC.MP/obj/Makefile	Thu Jul 18 10:19:11 2019
+++ /usr/share/relink/kernel/GENERIC.MP/Makefile	Fri Jul 19 18:13:10 2019
@@ -1124,7 +1124,10 @@ locore.o: assym.h
 	   echo "#GP-on-iretq fault handling would be broken"; exit 1; }
 
 ld.script: ${_machdir}/conf/ld.script
-	cp ${_machdir}/conf/ld.script $@
+	rm -f $@
+	/root/perform/makealign.sh ${_machdir}/conf/ld.script \
+	    ${SYSTEM_OBJ} vers.o swapgeneric.o >$@.tmp
+	mv $@.tmp $@
 
 gapdummy.o:
 	echo '__asm(".section .rodata,\"a\"");' > gapdummy.c
PATCH
}

# disable random sort of kernel object files, needed by reboot.pl
sub patch_makefile_norandom {
	return <<'PATCH';
--- /usr/src/sys/arch/amd64/compile/GENERIC.MP/obj/Makefile	Sat Jun  1 12:39:49 2019
+++ /usr/share/relink/kernel/GENERIC.MP/Makefile	Tue Jun  4 23:06:56 2019
@@ -50,7 +50,7 @@ CWARNFLAGS=	-Werror -Wall -Wimplicit-function-declarat
 CMACHFLAGS=	-mcmodel=kernel -mno-red-zone -mno-sse2 -mno-sse -mno-3dnow \
 		-mno-mmx -msoft-float -fno-omit-frame-pointer
 CMACHFLAGS+=	-ffreestanding ${NOPIE_FLAGS}
-SORTR=		sort -R
+SORTR=		sort
 .if ${IDENT:M-DNO_PROPOLICE}
 CMACHFLAGS+=	-fno-stack-protector
 .endif
PATCH
}

# disable random kernel kernel gap, needed by reboot.pl
sub patch_makegap_norandom {
	return <<'PATCH';
--- /usr/src/sys/conf/makegap.sh	Thu Jan 25 15:09:52 2018
+++ /usr/share/relink/kernel/GENERIC.MP/makegap.sh	Tue Jun  4 23:07:48 2019
@@ -1,15 +1,7 @@
 #!/bin/sh -
 
 random_uniform() {
-	local	_upper_bound
-
-	if [[ $1 -gt 0 ]]; then
-		_upper_bound=$(($1 - 1))
-	else
-		_upper_bound=0
-	fi
-
-	echo `jot -r 1 0 $_upper_bound 2>/dev/null`
+	echo 0
 }
 
 umask 007
PATCH
}

# Checking out with existing vendor branch and commits on top was broken.
# This is needed to cvs update llvm.
sub patch_cvs_vendor {
	return <<'PATCH';
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
}

# A partial backout prevents kernel compilation.  Repair the tree
# when the first backout happend.
sub patch_sys_puc {
	return <<'PATCH';
Index: sys/dev/pci/puc.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/puc.c,v
retrieving revision 1.25
retrieving revision 1.26
diff -u -p -r1.25 -r1.26
--- sys/dev/pci/puc.c	15 Apr 2018 15:07:25 -0000	1.25
+++ sys/dev/pci/puc.c	2 May 2018 19:11:01 -0000	1.26
@@ -61,7 +61,6 @@
 #include <dev/pci/pcireg.h>
 #include <dev/pci/pcivar.h>
 #include <dev/pci/pucvar.h>
-#include <dev/pci/pcidevs.h>
 
 #include <dev/ic/comreg.h>
 #include <dev/ic/comvar.h>
@@ -79,7 +78,6 @@ int	puc_pci_detach(struct device *, int)
 const char *puc_pci_intr_string(struct puc_attach_args *);
 void	*puc_pci_intr_establish(struct puc_attach_args *, int,
     int (*)(void *), void *, char *);
-int	puc_pci_xr17v35x_intr(void *arg);
 
 struct cfattach puc_pci_ca = {
 	sizeof(struct puc_pci_softc), puc_pci_match,
@@ -127,20 +125,9 @@ puc_pci_intr_establish(struct puc_attach
 {
 	struct puc_pci_softc *sc = paa->puc;
 	struct puc_softc *psc = &sc->sc_psc;
-
-	if (psc->sc_xr17v35x) {
-		psc->sc_ports[paa->port].real_intrhand = func;
-		psc->sc_ports[paa->port].real_intrhand_arg = arg;
-		if (paa->port == 0)
-			psc->sc_ports[paa->port].intrhand =
-			    pci_intr_establish(sc->pc, sc->ih, type,
-			    puc_pci_xr17v35x_intr, sc, name);
-		return (psc->sc_ports[paa->port].real_intrhand);
-	} else {
-		psc->sc_ports[paa->port].intrhand =
-		    pci_intr_establish(sc->pc, sc->ih, type, func, arg, name);
-		return (psc->sc_ports[paa->port].intrhand);
-	}
+	
+	psc->sc_ports[paa->port].intrhand =
+	    pci_intr_establish(sc->pc, sc->ih, type, func, arg, name);
 
 	return (psc->sc_ports[paa->port].intrhand);
 }
@@ -159,10 +146,6 @@ puc_pci_attach(struct device *parent, st
 	sc->sc_desc = puc_find_description(PCI_VENDOR(pa->pa_id),
 	    PCI_PRODUCT(pa->pa_id), PCI_VENDOR(subsys), PCI_PRODUCT(subsys));
 
-	if (PCI_VENDOR(pa->pa_id) == PCI_VENDOR_EXAR &&
-	    PCI_PRODUCT(pa->pa_id) == PCI_PRODUCT_EXAR_XR17V354)
-		sc->sc_xr17v35x = 1;
-
 	puc_print_ports(sc->sc_desc);
 
 	for (i = 0; i < PUC_NBARS; i++) {
@@ -336,6 +319,7 @@ puc_find_description(u_int16_t vend, u_i
 const char *
 puc_port_type_name(int type)
 {
+
 	if (PUC_IS_COM(type))
 		return "com";
 	if (PUC_IS_LPT(type))
@@ -363,23 +347,4 @@ puc_print_ports(const struct puc_device_
 		printf("%d lpt", nlpt);
 	}
 	printf("\n");
-}
-
-int
-puc_pci_xr17v35x_intr(void *arg)
-{
-	struct puc_pci_softc *sc = arg;
-	struct puc_softc *psc = &sc->sc_psc;
-	int ports, i;
-
-	ports = bus_space_read_1(psc->sc_bar_mappings[0].t,
-	    psc->sc_bar_mappings[0].h, UART_EXAR_INT0);
-
-	for (i = 0; i < 8; i++) {
-		if ((ports & (1 << i)) && psc->sc_ports[i].real_intrhand)
-			(*(psc->sc_ports[i].real_intrhand))(
-			    psc->sc_ports[i].real_intrhand_arg);
-	}
-
-	return (1);
 }
Index: sys/dev/pci/pucdata.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/pucdata.c,v
retrieving revision 1.108
retrieving revision 1.109
diff -u -p -r1.108 -r1.109
--- sys/dev/pci/pucdata.c	15 Apr 2018 15:07:25 -0000	1.108
+++ sys/dev/pci/pucdata.c	2 May 2018 19:11:01 -0000	1.109
@@ -2062,10 +2062,10 @@ const struct puc_device_description puc_
 	    {   PCI_VENDOR_EXAR, PCI_PRODUCT_EXAR_XR17V354,	0, 0 },
 	    {   0xffff, 0xffff,					0, 0 },
 	    {
-		{ PUC_PORT_COM_125MHZ, 0x10, 0x0000 },
-		{ PUC_PORT_COM_125MHZ, 0x10, 0x0400 },
-		{ PUC_PORT_COM_125MHZ, 0x10, 0x0800 },
-		{ PUC_PORT_COM_125MHZ, 0x10, 0x0C00 },
+		{ PUC_PORT_COM_MUL8, 0x10, 0x0000 },
+		{ PUC_PORT_COM_MUL8, 0x10, 0x0400 },
+		{ PUC_PORT_COM_MUL8, 0x10, 0x0800 },
+		{ PUC_PORT_COM_MUL8, 0x10, 0x0C00 },
 	    },
 	},
 
Index: sys/dev/pci/pucvar.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/pucvar.h,v
retrieving revision 1.15
retrieving revision 1.16
diff -u -p -r1.15 -r1.16
--- sys/dev/pci/pucvar.h	15 Apr 2018 15:07:25 -0000	1.15
+++ sys/dev/pci/pucvar.h	2 May 2018 19:11:01 -0000	1.16
@@ -72,7 +72,6 @@ static const struct puc_port_type puc_po
 	{ PUC_PORT_COM_MUL8,	COM_FREQ * 8	},
 	{ PUC_PORT_COM_MUL10,	COM_FREQ * 10	},
 	{ PUC_PORT_COM_MUL128,	COM_FREQ * 128	},
-	{ PUC_PORT_COM_125MHZ,	125000000	},
 };
 
 #define PUC_IS_LPT(type)	((type) == PUC_PORT_LPT)
@@ -118,11 +117,7 @@ struct puc_softc {
 		struct device   *dev;
 		/* filled in by port attachments */
 		void	*intrhand;
-		int	(*real_intrhand)(void *);
-		void	*real_intrhand_arg;
 	} sc_ports[PUC_MAX_PORTS];
-
-	int			sc_xr17v35x;
 };
 
 const struct puc_device_description *
PATCH
}

# Accidental garbage commited near the RCS Id prevents further checkout
# and configuring the kernel.  Patch it at the right spot.
sub patch_sys_garbage {
	return <<'PATCH';
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
}

# The first attempt to implement clang -msave-args contained bugs.
# Fix them early to prevent a buggy compiler.
sub patch_llvm_save_func {
	return <<'PATCH';
Index: gnu/llvm/lib/Target/X86/X86FrameLowering.cpp
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/gnu/llvm/lib/Target/X86/X86FrameLowering.cpp,v
retrieving revision 1.6
retrieving revision 1.7
diff -u -p -r1.6 -r1.7
--- gnu/llvm/lib/Target/X86/X86FrameLowering.cpp	30 Jan 2019 03:08:12 -0000	1.6
+++ gnu/llvm/lib/Target/X86/X86FrameLowering.cpp	5 Feb 2019 02:12:41 -0000	1.7
@@ -1750,7 +1750,7 @@ void X86FrameLowering::emitEpilogue(Mach
 
     if (X86FI->getSaveArgSize()) {
       // LEAVE is effectively mov rbp,rsp; pop rbp
-      BuildMI(MBB, MBBI, DL, TII.get(X86::LEAVE64), MachineFramePtr)
+      BuildMI(MBB, MBBI, DL, TII.get(X86::LEAVE64))
         .setMIFlag(MachineInstr::FrameDestroy);
     } else {
       // Pop EBP.
Index: gnu/llvm/lib/Target/X86/X86Subtarget.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/gnu/llvm/lib/Target/X86/X86Subtarget.h,v
retrieving revision 1.4
retrieving revision 1.5
diff -u -p -r1.4 -r1.5
--- gnu/llvm/lib/Target/X86/X86Subtarget.h	30 Jan 2019 03:08:12 -0000	1.4
+++ gnu/llvm/lib/Target/X86/X86Subtarget.h	4 Feb 2019 17:08:56 -0000	1.5
@@ -401,7 +401,7 @@ protected:
   unsigned stackAlignment = 4;
 
   /// Whether function prologues should save register arguments on the stack.
-  unsigned SaveArgs;
+  bool SaveArgs = false;
 
   /// Max. memset / memcpy size that is turned into rep/movs, rep/stos ops.
   ///
@@ -481,7 +481,7 @@ public:
     return &getInstrInfo()->getRegisterInfo();
   }
 
-  unsigned getSaveArgs() const { return SaveArgs; }
+  bool getSaveArgs() const { return SaveArgs; }
 
   /// Returns the minimum alignment known to hold of the
   /// stack frame on entry to the function and which must be maintained by every
PATCH
}

# Add ucrcom(4) a (very simple) driver for the serial console of (some)
sub patch_sys_files_ucrcom {
	return <<'PATCH';
Index: sys/dev/usb/files.usb
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/usb/files.usb,v
retrieving revision 1.137
retrieving revision 1.138
diff -u -p -r1.137 -r1.138
--- sys/dev/usb/files.usb	27 Mar 2019 22:08:51 -0000	1.137
+++ sys/dev/usb/files.usb	9 May 2019 00:20:57 -0000	1.138
@@ -341,6 +341,11 @@ file	dev/usb/umcs.c			umcs
 device	uscom: ucombus
 attach	uscom at uhub
 file	dev/usb/uscom.c			uscom
+
+# Chromebook serial
+device	ucrcom: ucombus
+attach	ucrcom at uhub
+file	dev/usb/ucrcom.c		ucrcom
 
 # Exar XR21V1410
 device	uxrcom: ucombus
PATCH
}

sub patch_sys_sys_time {
	return <<'PATCH';
Index: sys/sys/time.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/sys/time.h,v
retrieving revision 1.44
retrieving revision 1.45
diff -u -p -r1.44 -r1.45
--- sys/sys/time.h	3 Jul 2019 22:39:33 -0000	1.44
+++ sys/sys/time.h	2 Aug 2019 03:33:15 -0000	1.45
@@ -298,7 +298,7 @@ struct proc;
 int	clock_gettime(struct proc *, clockid_t, struct timespec *);
 
 int	itimerfix(struct timeval *);
-int	itimerdecr(struct itimerval *itp, int usec);
+int	itimerdecr(struct itimerspec *itp, long nsec);
 void	itimerround(struct timeval *);
 int	settime(const struct timespec *);
 int	ratecheck(struct timeval *, const struct timeval *);
PATCH
}

# Supermicro X8DTH-i/6/iF/6F fails to attach uhci(4) via PCI and AHCI.
sub patch_sys_uhci_activate {
	return <<'PATCH';
Index: sys/dev/pci/uhci_pci.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/uhci_pci.c,v
retrieving revision 1.33
retrieving revision 1.34
diff -u -p -r1.33 -r1.34
--- sys/dev/pci/uhci_pci.c	16 May 2014 18:17:03 -0000	1.33
+++ sys/dev/pci/uhci_pci.c	5 Sep 2019 17:59:12 -0000	1.34
@@ -86,6 +86,9 @@ uhci_pci_activate(struct device *self, i
 {
 	struct uhci_pci_softc *sc = (struct uhci_pci_softc *)self;
 
+	if (sc->sc.sc_size == 0)
+		return 0;
+
 	/* On resume, set legacy support attribute and enable intrs */
 	switch (act) {
 	case DVACT_RESUME:
@@ -190,6 +193,7 @@ uhci_pci_attach(struct device *parent, s
 
 unmap_ret:
 	bus_space_unmap(sc->sc.iot, sc->sc.ioh, sc->sc.sc_size);
+	sc->sc.sc_size = 0;
 	splx(s);
 }
 
@@ -218,6 +222,7 @@ uhci_pci_attach_deferred(struct device *
 unmap_ret:
 	bus_space_unmap(sc->sc.iot, sc->sc.ioh, sc->sc.sc_size);
 	pci_intr_disestablish(sc->sc_pc, sc->sc_ih);
+	sc->sc.sc_size = 0;
 	splx(s);
 }
 
PATCH
}

# Fix previous commit: missed a ds_copyin() moved in rev 1.72
sub patch_sys_shm_copyin {
	return <<'PATCH';
Index: sys/kern/sysv_shm.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/kern/sysv_shm.c,v
retrieving revision 1.73
retrieving revision 1.74
diff -u -p -r1.73 -r1.74
--- sys/kern/sysv_shm.c	3 Nov 2019 20:16:01 -0000	1.73
+++ sys/kern/sysv_shm.c	4 Nov 2019 00:48:22 -0000	1.74
@@ -296,7 +296,7 @@ sys_shmctl(struct proc *p, void *v, regi
 	int		error;
 
 	if (cmd == IPC_SET) {
-		error = ds_copyin(buf, &inbuf, sizeof(inbuf));
+		error = copyin(buf, &inbuf, sizeof(inbuf));
 		if (error)
 			return (error);
 	}
PATCH
}

# Fix previous commit: in ix(4) use the system stoeplitz key
sub patch_sys_ix_toeplitz {
	return <<'PATCH';
Index: sys/dev/pci/ixgbe.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/ixgbe.h,v
retrieving revision 1.30
retrieving revision 1.31
diff -u -p -r1.30 -r1.31
--- sys/dev/pci/ixgbe.h	17 Jul 2020 06:27:36 -0000	1.30
+++ sys/dev/pci/ixgbe.h	17 Jul 2020 07:49:49 -0000	1.31
@@ -58,6 +58,7 @@
 
 #include <net/if.h>
 #include <net/if_media.h>
+#include <net/toeplitz.h>
 
 #include <netinet/in.h>
 #include <netinet/if_ether.h>
PATCH
}

# Backout previous try to fix: in ix(4) use the system stoeplitz key
sub patch_sys_ix_toeplitz_bad {
	return <<'PATCH';
Index: sys/dev/pci/if_ix.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/pci/if_ix.c,v
retrieving revision 1.170
retrieving revision 1.169
diff -u -p -r1.170 -r1.169
--- sys/dev/pci/if_ix.c	17 Jul 2020 07:40:35 -0000	1.170
+++ sys/dev/pci/if_ix.c	17 Jul 2020 06:33:07 -0000	1.169
@@ -33,8 +33,6 @@
 
 ******************************************************************************/
 /* FreeBSD: src/sys/dev/ixgbe/ixgbe.c 251964 Jun 18 21:28:19 2013 UTC */
-
-#include <net/toeplitz.h>
 
 #include <dev/pci/if_ix.h>
 #include <dev/pci/ixgbe_type.h>
PATCH
}

# Fix loading pf rules.  Relax check for valid onrdomain range.
sub patch_sys_pf_rdomain {
	return <<'PATCH';
Index: sys/net/pf_ioctl.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/pf_ioctl.c,v
retrieving revision 1.357
retrieving revision 1.358
diff -u -p -r1.357 -r1.358
--- sys/net/pf_ioctl.c	1 Oct 2020 14:02:08 -0000	1.357
+++ sys/net/pf_ioctl.c	2 Oct 2020 09:14:33 -0000	1.358
@@ -2820,7 +2820,8 @@ pf_rule_copyin(struct pf_rule *from, str
 	if (to->rtableid >= 0 && !rtable_exists(to->rtableid))
 		return (EBUSY);
 	to->onrdomain = from->onrdomain;
-	if (to->onrdomain < 0 || to->onrdomain > RT_TABLEID_MAX)
+	if (to->onrdomain != -1 && (to->onrdomain < 0 ||
+	    to->onrdomain > RT_TABLEID_MAX))
 		return (EINVAL);
 
 	for (i = 0; i < PFTM_MAX; i++)
PATCH
}

# Remove last dangling usage of CRYPTO_F_NOQUEUE.
sub patch_sys_softraid_crypto {
	return <<'PATCH';
Index: sys/dev/softraid_crypto.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/dev/softraid_crypto.c,v
retrieving revision 1.142
retrieving revision 1.143
diff -u -p -r1.142 -r1.143
--- sys/dev/softraid_crypto.c	13 Oct 2021 22:43:44 -0000	1.142
+++ sys/dev/softraid_crypto.c	22 Oct 2021 05:06:37 -0000	1.143
@@ -325,7 +325,7 @@ sr_crypto_prepare(struct sr_workunit *wu
 	crwu->cr_crp->crp_opaque = crwu;
 	crwu->cr_crp->crp_ilen = xs->datalen;
 	crwu->cr_crp->crp_alloctype = M_DEVBUF;
-	crwu->cr_crp->crp_flags = CRYPTO_F_IOV | CRYPTO_F_NOQUEUE;
+	crwu->cr_crp->crp_flags = CRYPTO_F_IOV;
 	crwu->cr_crp->crp_buf = &crwu->cr_uio;
 	for (i = 0; i < crwu->cr_crp->crp_ndesc; i++, blkno++) {
 		crd = &crwu->cr_crp->crp_desc[i];
PATCH
}

# Revert previous. Breaks probing native IDE devices.
sub patch_sys_scsi_link {
	return <<'PATCH';
Index: sys/scsi/scsiconf.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/scsi/scsiconf.c,v
retrieving revision 1.247
retrieving revision 1.248
diff -u -p -r1.247 -r1.248
--- sys/scsi/scsiconf.c	23 Mar 2022 14:36:01 -0000	1.247
+++ sys/scsi/scsiconf.c	24 Mar 2022 00:30:51 -0000	1.248
@@ -519,8 +519,7 @@ scsi_probe_link(struct scsibus_softc *sb
 			SC_DEBUG(link, SDEV_DB2, ("dev_probe(link) failed.\n"));
 			rslt = EINVAL;
 		}
-		free(link, M_DEVBUF, sizeof(*link));
-		return rslt;
+		goto free;
 	}
 
 	/*
@@ -623,7 +622,7 @@ scsi_probe_link(struct scsibus_softc *sb
 		/* The device doesn't distinguish between LUNs. */
 		SC_DEBUG(link, SDEV_DB1, ("IDENTIFY not supported.\n"));
 		rslt = EINVAL;
-		goto bad;
+		goto free_devid;
 	}
 
 	link->quirks = devquirks;	/* Restore what the device wanted. */
@@ -680,7 +679,7 @@ scsi_probe_link(struct scsibus_softc *sb
 	if (cf == NULL) {
 		scsibussubprint(&sa, sb->sc_dev.dv_xname);
 		printf(" not configured\n");
-		goto bad;
+		goto free_devid;
 	}
 
 	/*
@@ -718,8 +717,17 @@ scsi_probe_link(struct scsibus_softc *sb
 	config_attach((struct device *)sb, cf, &sa, scsibussubprint);
 	return 0;
 
+free_devid:
+	if (link->id)
+		devid_free(link->id);
 bad:
-	scsi_detach_link(link, DETACH_FORCE);
+	if (ISSET(link->flags, SDEV_OWN_IOPL))
+		free(link->pool, M_DEVBUF, sizeof(*link->pool));
+
+	if (sb->sb_adapter->dev_free != NULL)
+		sb->sb_adapter->dev_free(link);
+free:
+	free(link, M_DEVBUF, sizeof(*link));
 	return rslt;
 }
 
PATCH
}

# Fix build after 1.298
sub patch_sys_pledge_nodelay {
	return <<'PATCH';
Index: sys/kern/kern_pledge.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/kern/kern_pledge.c,v
retrieving revision 1.298
retrieving revision 1.299
diff -u -p -r1.298 -r1.299
--- sys/kern/kern_pledge.c	9 Nov 2022 22:25:08 -0000	1.298
+++ sys/kern/kern_pledge.c	10 Nov 2022 00:14:11 -0000	1.299
@@ -1378,6 +1378,7 @@ pledge_sockopt(struct proc *p, int set, 
 		switch (optname) {
 		case TCP_NODELAY:
 			return (0);
+		}
 		break;
 	}
 
PATCH
}

# Fix build after 1.16
sub patch_sys_pfvar_annotations {
	return <<'PATCH';
Index: sys/net/pfvar_priv.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/pfvar_priv.h,v
retrieving revision 1.16
retrieving revision 1.17
diff -u -p -r1.16 -r1.17
--- sys/net/pfvar_priv.h	11 Nov 2022 12:29:32 -0000	1.16
+++ sys/net/pfvar_priv.h	11 Nov 2022 12:36:05 -0000	1.17
@@ -60,7 +60,7 @@ struct pf_state {
 	TAILQ_ENTRY(pf_state)	 entry_list;	/* (L) */
 	SLIST_ENTRY(pf_state)	 gc_list;	/* (g) */
 	RB_ENTRY(pf_state)	 entry_id;	/* (P) */
-	struct pf_state_peer	 src(;
+	struct pf_state_peer	 src;
 	struct pf_state_peer	 dst;
 	struct pf_rule_slist	 match_rules;	/* (I) */
 	union pf_rule_ptr	 rule;		/* (I) */
PATCH
}

# Fix hang in pf purge after moving pf_purge() to systqmp, remove net lock
sub patch_sys_pf_purge {
	return <<'PATCH';
Index: sys/net/pf.c
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/pf.c,v
retrieving revision 1.1152
diff -u -p -r1.1152 pf.c
--- sys/net/pf.c	11 Nov 2022 16:12:08 -0000	1.1152
+++ sys/net/pf.c	22 Nov 2022 14:05:27 -0000
@@ -1601,20 +1601,14 @@ pf_purge(void *null)
 {
 	unsigned int interval = max(1, pf_default_rule.timeout[PFTM_INTERVAL]);
 
-	/* XXX is NET_LOCK necessary? */
-	NET_LOCK();
-
-	PF_LOCK();
-
+	rw_enter_write(&pf_lock); /* PF_LOCK() without NET_LOCK() */
 	pf_purge_expired_src_nodes();
-
-	PF_UNLOCK();
+	rw_exit_write(&pf_lock); /* PF_UNLOCK() without NET_LOCK() */
 
 	/*
 	 * Fragments don't require PF_LOCK(), they use their own lock.
 	 */
 	pf_purge_expired_fragments();
-	NET_UNLOCK();
 
 	/* interpret the interval as idle time between runs */
 	timeout_add_sec(&pf_purge_to, interval);
@@ -1889,9 +1883,8 @@ pf_purge_expired_states(const unsigned i
 	if (SLIST_EMPTY(&gcl))
 		return (scanned);
 
-	NET_LOCK();
 	rw_enter_write(&pf_state_list.pfs_rwl);
-	PF_LOCK();
+	rw_enter_write(&pf_lock); /* PF_LOCK() without NET_LOCK() */
 	PF_STATE_ENTER_WRITE();
 	SLIST_FOREACH(st, &gcl, gc_list) {
 		if (st->timeout != PFTM_UNLINKED)
@@ -1900,9 +1893,8 @@ pf_purge_expired_states(const unsigned i
 		pf_free_state(st);
 	}
 	PF_STATE_EXIT_WRITE();
-	PF_UNLOCK();
+	rw_exit_write(&pf_lock); /* PF_UNLOCK() without NET_LOCK() */
 	rw_exit_write(&pf_state_list.pfs_rwl);
-	NET_UNLOCK();
 
 	while ((st = SLIST_FIRST(&gcl)) != NULL) {
 		SLIST_REMOVE_HEAD(&gcl, gc_list);
PATCH
}

# revert r1.673: replace SRP with SMR in the if_idxmap, hang during boot
sub patch_sys_if_srp_smr {
	return <<'PATCH';
Index: sys/net/if.c
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/if.c,v
retrieving revision 1.675
retrieving revision 1.676
diff -u -p -r1.675 -r1.676
--- sys/net/if.c	9 Nov 2022 13:09:30 -0000	1.675
+++ sys/net/if.c	9 Nov 2022 22:15:50 -0000	1.676
@@ -87,7 +87,6 @@
 #include <sys/proc.h>
 #include <sys/stdint.h>	/* uintptr_t */
 #include <sys/rwlock.h>
-#include <sys/smr.h>
 
 #include <net/if.h>
 #include <net/if_dl.h>
@@ -197,20 +196,29 @@ void if_map_dtor(void *, void *);
 struct ifnet *if_ref(struct ifnet *);
 
 /*
+ * struct if_map
+ *
+ * bounded array of ifnet srp pointers used to fetch references of live
+ * interfaces with if_get().
+ */
+
+struct if_map {
+	unsigned long		 limit;
+	/* followed by limit ifnet srp pointers */
+};
+
+/*
  * struct if_idxmap
  *
  * infrastructure to manage updates and accesses to the current if_map.
- *
- * interface index 0 is special and represents "no interface", so we
- * use the 0th slot in map to store the length of the array.
  */
 
 struct if_idxmap {
-	unsigned int		  serial;
-	unsigned int		  count;
-	struct ifnet		**map;		/* SMR protected */
-	struct rwlock		  lock;
-	unsigned char		 *usedidx;	/* bitmap of indices in use */
+	unsigned int		 serial;
+	unsigned int		 count;
+	struct srp		 map;
+	struct rwlock		 lock;
+	unsigned char		*usedidx;	/* bitmap of indices in use */
 };
 
 void	if_idxmap_init(unsigned int);
@@ -257,7 +265,7 @@ ifinit(void)
 	 * most machines boot with 4 or 5 interfaces, so size the initial map
 	 * to accommodate this
 	 */
-	if_idxmap_init(8); /* 8 is a nice power of 2 for malloc */
+	if_idxmap_init(8);
 
 	for (i = 0; i < NET_TASKQ; i++) {
 		nettqmp[i] = taskq_create("softnet", 1, IPL_NET, TASKQ_MPSAFE);
@@ -266,41 +274,48 @@ ifinit(void)
 	}
 }
 
-static struct if_idxmap if_idxmap;
+static struct if_idxmap if_idxmap = {
+	0,
+	0,
+	SRP_INITIALIZER(),
+	RWLOCK_INITIALIZER("idxmaplk"),
+	NULL,
+};
 
-struct ifnet_head ifnetlist = TAILQ_HEAD_INITIALIZER(ifnetlist);
+struct srp_gc if_ifp_gc = SRP_GC_INITIALIZER(if_ifp_dtor, NULL);
+struct srp_gc if_map_gc = SRP_GC_INITIALIZER(if_map_dtor, NULL);
 
-static inline unsigned int
-if_idxmap_limit(struct ifnet **if_map)
-{
-	return ((uintptr_t)if_map[0]);
-}
+struct ifnet_head ifnetlist = TAILQ_HEAD_INITIALIZER(ifnetlist);
 
 void
 if_idxmap_init(unsigned int limit)
 {
-	struct ifnet **if_map;
+	struct if_map *if_map;
+	struct srp *map;
+	unsigned int i;
 
-	rw_init(&if_idxmap.lock, "idxmaplk");
-	if_idxmap.serial = 1; /* skip ifidx 0 */
+	if_idxmap.serial = 1; /* skip ifidx 0 so it can return NULL */
 
-	if_map = mallocarray(limit, sizeof(*if_map), M_IFADDR,
-	    M_WAITOK | M_ZERO);
+	if_map = malloc(sizeof(*if_map) + limit * sizeof(*map),
+	    M_IFADDR, M_WAITOK);
 
-	if_map[0] = (struct ifnet *)(uintptr_t)limit;
+	if_map->limit = limit;
+	map = (struct srp *)(if_map + 1);
+	for (i = 0; i < limit; i++)
+		srp_init(&map[i]);
 
 	if_idxmap.usedidx = malloc(howmany(limit, NBBY),
 	    M_IFADDR, M_WAITOK | M_ZERO);
 
 	/* this is called early so there's nothing to race with */
-	SMR_PTR_SET_LOCKED(&if_idxmap.map, if_map);
+	srp_update_locked(&if_map_gc, &if_idxmap.map, if_map);
 }
 
 void
 if_idxmap_alloc(struct ifnet *ifp)
 {
-	struct ifnet **if_map, **oif_map = NULL;
-	unsigned int limit, olimit;
+	struct if_map *if_map;
+	struct srp *map;
 	unsigned int index, i;
 
 	refcnt_init(&ifp->if_refcnt);
@@ -310,41 +325,49 @@ if_idxmap_alloc(struct ifnet *ifp)
 	if (++if_idxmap.count >= USHRT_MAX)
 		panic("too many interfaces");
 
-	if_map = SMR_PTR_GET_LOCKED(&if_idxmap.map);
-	limit = if_idxmap_limit(if_map);
+	if_map = srp_get_locked(&if_idxmap.map);
+	map = (struct srp *)(if_map + 1);
 
 	index = if_idxmap.serial++ & USHRT_MAX;
 
-	if (index >= limit) {
+	if (index >= if_map->limit) {
+		struct if_map *nif_map;
+		struct srp *nmap;
+		unsigned int nlimit;
+		struct ifnet *nifp;
 		unsigned char *nusedidx;
 
-		oif_map = if_map;
-		olimit = limit;
-
-		limit = olimit * 2;
-		if_map = mallocarray(limit, sizeof(*if_map), M_IFADDR,
-		    M_WAITOK | M_ZERO);
-		if_map[0] = (struct ifnet *)(uintptr_t)limit;
-		
-		for (i = 1; i < olimit; i++) {
-			struct ifnet *oifp = SMR_PTR_GET_LOCKED(&oif_map[i]);
-			if (oifp == NULL)
-				continue;
+		nlimit = if_map->limit * 2;
+		nif_map = malloc(sizeof(*nif_map) + nlimit * sizeof(*nmap),
+		    M_IFADDR, M_WAITOK);
+		nmap = (struct srp *)(nif_map + 1);
+
+		nif_map->limit = nlimit;
+		for (i = 0; i < if_map->limit; i++) {
+			srp_init(&nmap[i]);
+			nifp = srp_get_locked(&map[i]);
+			if (nifp != NULL) {
+				srp_update_locked(&if_ifp_gc, &nmap[i],
+				    if_ref(nifp));
+			}
+		}
 
-			/*
-			 * nif_map isn't visible yet, so don't need
-			 * SMR_PTR_SET_LOCKED and its membar.
-			 */
-			if_map[i] = if_ref(oifp);
+		while (i < nlimit) {
+			srp_init(&nmap[i]);
+			i++;
 		}
 
-		nusedidx = malloc(howmany(limit, NBBY),
+		nusedidx = malloc(howmany(nlimit, NBBY),
 		    M_IFADDR, M_WAITOK | M_ZERO);
-		memcpy(nusedidx, if_idxmap.usedidx, howmany(olimit, NBBY));
-		free(if_idxmap.usedidx, M_IFADDR, howmany(olimit, NBBY));
+		memcpy(nusedidx, if_idxmap.usedidx,
+		    howmany(if_map->limit, NBBY));
+		free(if_idxmap.usedidx, M_IFADDR,
+		    howmany(if_map->limit, NBBY));
 		if_idxmap.usedidx = nusedidx;
 
-		SMR_PTR_SET_LOCKED(&if_idxmap.map, if_map);
+		srp_update_locked(&if_map_gc, &if_idxmap.map, nif_map);
+		if_map = nif_map;
+		map = nmap;
 	}
 
 	/* pick the next free index */
@@ -354,40 +377,32 @@ if_idxmap_alloc(struct ifnet *ifp)
 
 		index = if_idxmap.serial++ & USHRT_MAX;
 	}
-	KASSERT(index != 0 && index < limit);
+	KASSERT(index != 0 && index < if_map->limit);
 	KASSERT(isclr(if_idxmap.usedidx, index));
 
 	setbit(if_idxmap.usedidx, index);
 	ifp->if_index = index;
 
 	rw_exit_write(&if_idxmap.lock);
-
-	if (oif_map != NULL) {
-		smr_barrier();
-		for (i = 1; i < olimit; i++)
-			if_put(oif_map[i]);
-		free(oif_map, M_IFADDR, olimit * sizeof(*oif_map));
-	}
 }
 
 void
 if_idxmap_insert(struct ifnet *ifp)
 {
-	struct ifnet **if_map;
+	struct if_map *if_map;
+	struct srp *map;
 	unsigned int index = ifp->if_index;
 
 	rw_enter_write(&if_idxmap.lock);
 
-	if_map = SMR_PTR_GET_LOCKED(&if_idxmap.map);
+	if_map = srp_get_locked(&if_idxmap.map);
+	map = (struct srp *)(if_map + 1);
 
-	KASSERTMSG(index != 0 && index < if_idxmap_limit(if_map),
-	    "%s(%p) index %u vs limit %u", ifp->if_xname, ifp, index,
-	    if_idxmap_limit(if_map));
-	KASSERT(SMR_PTR_GET_LOCKED(&if_map[index]) == NULL);
+	KASSERT(index != 0 && index < if_map->limit);
 	KASSERT(isset(if_idxmap.usedidx, index));
 
 	/* commit */
-	SMR_PTR_SET_LOCKED(&if_map[index], if_ref(ifp));
+	srp_update_locked(&if_ifp_gc, &map[index], if_ref(ifp));
 
 	rw_exit_write(&if_idxmap.lock);
 }
@@ -395,29 +410,53 @@ if_idxmap_insert(struct ifnet *ifp)
 void
 if_idxmap_remove(struct ifnet *ifp)
 {
-	struct ifnet **if_map;
-	unsigned int index = ifp->if_index;
+	struct if_map *if_map;
+	struct srp *map;
+	unsigned int index;
 
-	rw_enter_write(&if_idxmap.lock);
+	index = ifp->if_index;
 
-	if_map = SMR_PTR_GET_LOCKED(&if_idxmap.map);
+	rw_enter_write(&if_idxmap.lock);
 
-	KASSERT(index != 0 && index < if_idxmap_limit(if_map));
-	KASSERT(SMR_PTR_GET_LOCKED(&if_map[index]) == ifp);
-	KASSERT(isset(if_idxmap.usedidx, index));
+	if_map = srp_get_locked(&if_idxmap.map);
+	KASSERT(index < if_map->limit);
 
-	SMR_PTR_SET_LOCKED(&if_map[index], NULL);
+	map = (struct srp *)(if_map + 1);
+	KASSERT(ifp == (struct ifnet *)srp_get_locked(&map[index]));
 
+	srp_update_locked(&if_ifp_gc, &map[index], NULL);
 	if_idxmap.count--;
+
+	KASSERT(isset(if_idxmap.usedidx, index));
 	clrbit(if_idxmap.usedidx, index);
 	/* end of if_idxmap modifications */
 
 	rw_exit_write(&if_idxmap.lock);
+}
 
-	smr_barrier();
+void
+if_ifp_dtor(void *null, void *ifp)
+{
 	if_put(ifp);
 }
 
+void
+if_map_dtor(void *null, void *m)
+{
+	struct if_map *if_map = m;
+	struct srp *map = (struct srp *)(if_map + 1);
+	unsigned int i;
+
+	/*
+	 * dont need to serialize the use of update_locked since this is
+	 * the last reference to this map. there's nothing to race against.
+	 */
+	for (i = 0; i < if_map->limit; i++)
+		srp_update_locked(&if_ifp_gc, &map[i], NULL);
+
+	free(if_map, M_IFADDR, sizeof(*if_map) + if_map->limit * sizeof(*map));
+}
+
 /*
  * Attach an interface to the
  * list of "active" interfaces.
@@ -931,6 +970,14 @@ if_netisr(void *unused)
 		t |= n;
 	}
 
+#if NPFSYNC > 0
+	if (t & (1 << NETISR_PFSYNC)) {
+		KERNEL_LOCK();
+		pfsyncintr();
+		KERNEL_UNLOCK();
+	}
+#endif
+
 	NET_UNLOCK();
 }
 
@@ -1733,22 +1780,22 @@ if_unit(const char *name)
 struct ifnet *
 if_get(unsigned int index)
 {
-	struct ifnet **if_map;
+	struct srp_ref sr;
+	struct if_map *if_map;
+	struct srp *map;
 	struct ifnet *ifp = NULL;
 
-	if (index == 0)
-		return (NULL);
+	if_map = srp_enter(&sr, &if_idxmap.map);
+	if (index < if_map->limit) {
+		map = (struct srp *)(if_map + 1);
 
-	smr_read_enter();
-	if_map = SMR_PTR_GET(&if_idxmap.map);
-	if (index < if_idxmap_limit(if_map)) {
-		ifp = SMR_PTR_GET(&if_map[index]);
+		ifp = srp_follow(&sr, &map[index]);
 		if (ifp != NULL) {
 			KASSERT(ifp->if_index == index);
 			if_ref(ifp);
 		}
 	}
-	smr_read_leave();
+	srp_leave(&sr);
 
 	return (ifp);
 }
PATCH
}

# revert pf.c r1.1152 again: move pf_purge out from under the kernel lock
sub patch_sys_pf_purge_backout {
	return <<'PATCH';
Index: sys/net/pf.c
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/pf.c,v
retrieving revision 1.1155
diff -u -p -r1.1155 pf.c
--- sys/net/pf.c	25 Nov 2022 18:03:53 -0000	1.1155
+++ sys/net/pf.c	25 Nov 2022 18:53:32 -0000
@@ -120,6 +120,10 @@ u_char			 pf_tcp_secret[16];
 int			 pf_tcp_secret_init;
 int			 pf_tcp_iss_off;
 
+int		 pf_npurge;
+struct task	 pf_purge_task = TASK_INITIALIZER(pf_purge, &pf_npurge);
+struct timeout	 pf_purge_to = TIMEOUT_INITIALIZER(pf_purge_timeout, NULL);
+
 enum pf_test_status {
 	PF_TEST_FAIL = -1,
 	PF_TEST_OK,
@@ -1516,110 +1520,47 @@ pf_state_import(const struct pfsync_stat
 
 /* END state table stuff */
 
-void		 pf_purge_states(void *);
-struct task	 pf_purge_states_task =
-		     TASK_INITIALIZER(pf_purge_states, NULL);
-
-void		 pf_purge_states_tick(void *);
-struct timeout	 pf_purge_states_to =
-		     TIMEOUT_INITIALIZER(pf_purge_states_tick, NULL);
-
-unsigned int	 pf_purge_expired_states(unsigned int, unsigned int);
-
-/*
- * how many states to scan this interval.
- *
- * this is set when the timeout fires, and reduced by the task. the
- * task will reschedule itself until the limit is reduced to zero,
- * and then it adds the timeout again.
- */
-unsigned int pf_purge_states_limit;
-
-/*
- * limit how many states are processed with locks held per run of
- * the state purge task.
- */
-unsigned int pf_purge_states_collect = 64;
-
 void
-pf_purge_states_tick(void *null)
+pf_purge_timeout(void *unused)
 {
-	unsigned int limit = pf_status.states;
-	unsigned int interval = pf_default_rule.timeout[PFTM_INTERVAL];
-
-	if (limit == 0) {
-		timeout_add_sec(&pf_purge_states_to, 1);
-		return;
-	}
-
-	/*
-	 * process a fraction of the state table every second
-	 */
-
-	if (interval > 1)
-		limit /= interval;
-
-	pf_purge_states_limit = limit;
-	task_add(systqmp, &pf_purge_states_task);
-}
-
-void
-pf_purge_states(void *null)
-{
-	unsigned int limit;
-	unsigned int scanned;
-
-	limit = pf_purge_states_limit;
-	if (limit < pf_purge_states_collect)
-		limit = pf_purge_states_collect;
-
-	scanned = pf_purge_expired_states(limit, pf_purge_states_collect);
-	if (scanned >= pf_purge_states_limit) {
-		/* we've run out of states to scan this "interval" */
-		timeout_add_sec(&pf_purge_states_to, 1);
-		return;
-	}
-
-	pf_purge_states_limit -= scanned;
-	task_add(systqmp, &pf_purge_states_task);
+	/* XXX move to systqmp to avoid KERNEL_LOCK */
+	task_add(systq, &pf_purge_task);
 }
 
-void		 pf_purge_tick(void *);
-struct timeout	 pf_purge_to =
-		     TIMEOUT_INITIALIZER(pf_purge_tick, NULL);
-
-void		 pf_purge(void *);
-struct task	 pf_purge_task =
-		     TASK_INITIALIZER(pf_purge, NULL);
-
 void
-pf_purge_tick(void *null)
+pf_purge(void *xnloops)
 {
-	task_add(systqmp, &pf_purge_task);
-}
+	int *nloops = xnloops;
 
-void
-pf_purge(void *null)
-{
-	unsigned int interval = max(1, pf_default_rule.timeout[PFTM_INTERVAL]);
+	/*
+	 * process a fraction of the state table every second
+	 * Note:
+	 *     we no longer need PF_LOCK() here, because
+	 *     pf_purge_expired_states() uses pf_state_lock to maintain
+	 *     consistency.
+	 */
+	if (pf_default_rule.timeout[PFTM_INTERVAL] > 0)
+		pf_purge_expired_states(1 + (pf_status.states
+		    / pf_default_rule.timeout[PFTM_INTERVAL]));
 
-	/* XXX is NET_LOCK necessary? */
 	NET_LOCK();
 
 	PF_LOCK();
-
-	pf_purge_expired_src_nodes();
-
+	/* purge other expired types every PFTM_INTERVAL seconds */
+	if (++(*nloops) >= pf_default_rule.timeout[PFTM_INTERVAL])
+		pf_purge_expired_src_nodes();
 	PF_UNLOCK();
 
 	/*
 	 * Fragments don't require PF_LOCK(), they use their own lock.
 	 */
-	pf_purge_expired_fragments();
+	if ((*nloops) >= pf_default_rule.timeout[PFTM_INTERVAL]) {
+		pf_purge_expired_fragments();
+		*nloops = 0;
+	}
 	NET_UNLOCK();
 
-	/* interpret the interval as idle time between runs */
-	timeout_add_sec(&pf_purge_to, interval);
+	timeout_add_sec(&pf_purge_to, 1);
 }
 
 int32_t
@@ -1819,8 +1760,8 @@ pf_free_state(struct pf_state *cur)
 	pf_status.states--;
 }
 
-unsigned int
-pf_purge_expired_states(const unsigned int limit, const unsigned int collect)
+void
+pf_purge_expired_states(u_int32_t maxcheck)
 {
 	/*
 	 * this task/thread/context/whatever is the only thing that
@@ -1834,8 +1775,6 @@ pf_purge_expired_states(const unsigned i
 	struct pf_state		*st;
 	SLIST_HEAD(pf_state_gcl, pf_state) gcl = SLIST_HEAD_INITIALIZER(gcl);
 	time_t			 now;
-	unsigned int		 scanned;
-	unsigned int		 collected = 0;
 
 	PF_ASSERT_UNLOCKED();
 
@@ -1849,7 +1788,7 @@ pf_purge_expired_states(const unsigned i
 	if (head == NULL) {
 		/* the list is empty */
 		rw_exit_read(&pf_state_list.pfs_rwl);
-		return (limit);
+		return;
 	}
 
 	/* (re)start at the front of the list */
@@ -1858,38 +1797,28 @@ pf_purge_expired_states(const unsigned i
 
 	now = getuptime();
 
-	for (scanned = 0; scanned < limit; scanned++) {
+	do {
 		uint8_t stimeout = cur->timeout;
-		unsigned int limited = 0;
 
 		if ((stimeout == PFTM_UNLINKED) ||
 		    (pf_state_expires(cur, stimeout) <= now)) {
 			st = pf_state_ref(cur);
 			SLIST_INSERT_HEAD(&gcl, st, gc_list);
-
-			if (++collected >= collect)
-				limited = 1;
 		}
 
 		/* don't iterate past the end of our view of the list */
 		if (cur == tail) {
-			scanned = limit;
 			cur = NULL;
 			break;
 		}
 
 		cur = TAILQ_NEXT(cur, entry_list);
-
-		/* don't spend too much time here. */
-		if (ISSET(READ_ONCE(curcpu()->ci_schedstate.spc_schedflags),
-		     SPCF_SHOULDYIELD) || limited)
-			break;
-	}
+	} while (maxcheck--);
 
 	rw_exit_read(&pf_state_list.pfs_rwl);
 
 	if (SLIST_EMPTY(&gcl))
-		return (scanned);
+		return;
 
 	NET_LOCK();
 	rw_enter_write(&pf_state_list.pfs_rwl);
@@ -1910,8 +1839,6 @@ pf_purge_expired_states(const unsigned i
 		SLIST_REMOVE_HEAD(&gcl, gc_list);
 		pf_state_unref(st);
 	}
-
-	return (scanned);
 }
 
 int
Index: sys/net/pf_ioctl.c
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/pf_ioctl.c,v
retrieving revision 1.391
diff -u -p -r1.391 pf_ioctl.c
--- sys/net/pf_ioctl.c	11 Nov 2022 16:12:08 -0000	1.391
+++ sys/net/pf_ioctl.c	25 Nov 2022 18:53:32 -0000
@@ -1145,7 +1145,6 @@ pfioctl(dev_t dev, u_long cmd, caddr_t a
 				pf_status.stateid = gettime();
 				pf_status.stateid = pf_status.stateid << 32;
 			}
-			timeout_add_sec(&pf_purge_states_to, 1);
 			timeout_add_sec(&pf_purge_to, 1);
 			pf_create_queues();
 			DPFPRINTF(LOG_NOTICE, "pf: started");
@@ -2741,9 +2740,8 @@ pfioctl(dev_t dev, u_long cmd, caddr_t a
 			pf_default_rule.timeout[i] =
 			    pf_default_rule_new.timeout[i];
 			if (pf_default_rule.timeout[i] == PFTM_INTERVAL &&
-			    pf_default_rule.timeout[i] < old &&
-			    timeout_del(&pf_purge_to))
-				task_add(systqmp, &pf_purge_task);
+			    pf_default_rule.timeout[i] < old)
+				task_add(net_tq(0), &pf_purge_task);
 		}
 		pfi_xcommit();
 		pf_trans_set_commit();
Index: sys/net/pfvar.h
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/pfvar.h,v
retrieving revision 1.520
diff -u -p -r1.520 pfvar.h
--- sys/net/pfvar.h	11 Nov 2022 16:12:08 -0000	1.520
+++ sys/net/pfvar.h	25 Nov 2022 18:53:32 -0000
@@ -1633,6 +1633,7 @@ extern void			 pf_tbladdr_remove(struct 
 extern void			 pf_tbladdr_copyout(struct pf_addr_wrap *);
 extern void			 pf_calc_skip_steps(struct pf_rulequeue *);
 extern void			 pf_purge_expired_src_nodes(void);
+extern void			 pf_purge_expired_states(u_int32_t);
 extern void			 pf_purge_expired_rules(void);
 extern void			 pf_remove_state(struct pf_state *);
 extern void			 pf_remove_divert_state(struct pf_state_key *);
Index: sys/net/pfvar_priv.h
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/net/pfvar_priv.h,v
retrieving revision 1.22
diff -u -p -r1.22 pfvar_priv.h
--- sys/net/pfvar_priv.h	24 Nov 2022 00:04:32 -0000	1.22
+++ sys/net/pfvar_priv.h	25 Nov 2022 18:53:32 -0000
@@ -267,7 +267,6 @@ struct pf_pdesc {
 	} hdr;
 };
 
-extern struct timeout	pf_purge_states_to;
 extern struct task	pf_purge_task;
 extern struct timeout	pf_purge_to;
 
@@ -319,6 +318,9 @@ extern struct rwlock	pf_state_lock;
 			splassert_fail(RW_WRITE,	\
 			    rw_status(&pf_state_lock), __func__);\
 	} while (0)
+
+extern void			 pf_purge_timeout(void *);
+extern void			 pf_purge(void *);
 
 /* for copies to/from network byte order */
 void			pf_state_peer_hton(const struct pf_state_peer *,
PATCH
}

# gap.o creates .plt section in kernel if built with fcf protection
# this leads to gaps in kernel image when creating aligned objects
sub patch_sys_amd64_cfgap {
	return <<'PATCH';
Index: sys/arch/amd64/conf/Makefile.amd64
===================================================================
RCS file: /mount/openbsd/cvs/src/sys/arch/amd64/conf/Makefile.amd64,v
retrieving revision 1.131
diff -u -p -r1.131 Makefile.amd64
--- sys/arch/amd64/conf/Makefile.amd64	17 Apr 2023 01:14:24 -0000	1.131
+++ sys/arch/amd64/conf/Makefile.amd64	20 Apr 2023 21:25:05 -0000
@@ -177,7 +177,7 @@ ld.script: ${_machdir}/conf/ld.script
 
 gapdummy.o:
 	echo '__asm(".section .rodata,\"a\"");' > gapdummy.c
-	${CC} -c ${CFLAGS} ${CPPFLAGS} gapdummy.c -o $@
+	${CC} -c ${CFLAGS} ${CPPFLAGS} -fcf-protection=none gapdummy.c -o $@
 
 makegap.sh:
 	cp $S/conf/makegap.sh $@
PATCH
}

# Backout always allocate per-CPU statistics counters for network
# interface descriptor.  It panics during attach of em(4) device at
# boot.
sub patch_sys_if_counters_backout {
	return <<'PATCH';
Index: sys/net/if.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if.c,v
diff -u -p -r1.712 if.c
--- sys/net/if.c	22 Dec 2023 23:01:50 -0000	1.712
+++ sys/net/if.c	23 Dec 2023 10:27:51 -0000
@@ -645,8 +645,6 @@ if_attach_common(struct ifnet *ifp)
 		    "%s: if_qstart not set with MPSAFE set", ifp->if_xname);
 	}
 
-	ifp->if_counters = counters_alloc(ifc_ncounters);
-
 	if_idxmap_alloc(ifp);
 
 	ifq_init(&ifp->if_snd, ifp, 0);
@@ -1252,7 +1250,8 @@ if_detach(struct ifnet *ifp)
 	/* Announce that the interface is gone. */
 	rtm_ifannounce(ifp, IFAN_DEPARTURE);
 
-	counters_free(ifp->if_counters, ifc_ncounters);
+	if (ifp->if_counters != NULL)
+		if_counters_free(ifp);
 
 	for (i = 0; i < ifp->if_nifqs; i++)
 		ifq_destroy(ifp->if_ifqs[i]);
@@ -2772,27 +2771,48 @@ ifconf(caddr_t data)
 }
 
 void
+if_counters_alloc(struct ifnet *ifp)
+{
+	KASSERT(ifp->if_counters == NULL);
+
+	ifp->if_counters = counters_alloc(ifc_ncounters);
+}
+
+void
+if_counters_free(struct ifnet *ifp)
+{
+	KASSERT(ifp->if_counters != NULL);
+
+	counters_free(ifp->if_counters, ifc_ncounters);
+	ifp->if_counters = NULL;
+}
+
+void
 if_getdata(struct ifnet *ifp, struct if_data *data)
 {
-	uint64_t counters[ifc_ncounters];
 	unsigned int i;
 
 	*data = ifp->if_data;
 
-	counters_read(ifp->if_counters, counters, nitems(counters), NULL);
+	if (ifp->if_counters != NULL) {
+		uint64_t counters[ifc_ncounters];
 
-	data->ifi_ipackets += counters[ifc_ipackets];
-	data->ifi_ierrors += counters[ifc_ierrors];
-	data->ifi_opackets += counters[ifc_opackets];
-	data->ifi_oerrors += counters[ifc_oerrors];
-	data->ifi_collisions += counters[ifc_collisions];
-	data->ifi_ibytes += counters[ifc_ibytes];
-	data->ifi_obytes += counters[ifc_obytes];
-	data->ifi_imcasts += counters[ifc_imcasts];
-	data->ifi_omcasts += counters[ifc_omcasts];
-	data->ifi_iqdrops += counters[ifc_iqdrops];
-	data->ifi_oqdrops += counters[ifc_oqdrops];
-	data->ifi_noproto += counters[ifc_noproto];
+		counters_read(ifp->if_counters, counters, nitems(counters),
+		    NULL);
+
+		data->ifi_ipackets += counters[ifc_ipackets];
+		data->ifi_ierrors += counters[ifc_ierrors];
+		data->ifi_opackets += counters[ifc_opackets];
+		data->ifi_oerrors += counters[ifc_oerrors];
+		data->ifi_collisions += counters[ifc_collisions];
+		data->ifi_ibytes += counters[ifc_ibytes];
+		data->ifi_obytes += counters[ifc_obytes];
+		data->ifi_imcasts += counters[ifc_imcasts];
+		data->ifi_omcasts += counters[ifc_omcasts];
+		data->ifi_iqdrops += counters[ifc_iqdrops];
+		data->ifi_oqdrops += counters[ifc_oqdrops];
+		data->ifi_noproto += counters[ifc_noproto];
+	}
 
 	for (i = 0; i < ifp->if_nifqs; i++) {
 		struct ifqueue *ifq = ifp->if_ifqs[i];
Index: sys/net/if_aggr.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_aggr.c,v
diff -u -p -r1.41 if_aggr.c
--- sys/net/if_aggr.c	22 Dec 2023 23:01:50 -0000	1.41
+++ sys/net/if_aggr.c	23 Dec 2023 10:27:51 -0000
@@ -562,6 +562,7 @@ aggr_clone_create(struct if_clone *ifc, 
 	ifp->if_link_state = LINK_STATE_DOWN;
 	ether_fakeaddr(ifp);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_bpe.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_bpe.c,v
diff -u -p -r1.21 if_bpe.c
--- sys/net/if_bpe.c	22 Dec 2023 23:01:50 -0000	1.21
+++ sys/net/if_bpe.c	23 Dec 2023 10:27:51 -0000
@@ -182,6 +182,7 @@ bpe_clone_create(struct if_clone *ifc, i
 	ifp->if_xflags = IFXF_CLONED;
 	ether_fakeaddr(ifp);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_etherip.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_etherip.c,v
diff -u -p -r1.53 if_etherip.c
--- sys/net/if_etherip.c	22 Dec 2023 23:01:50 -0000	1.53
+++ sys/net/if_etherip.c	23 Dec 2023 10:27:51 -0000
@@ -161,6 +161,7 @@ etherip_clone_create(struct if_clone *if
 	ifmedia_add(&sc->sc_media, IFM_ETHER | IFM_AUTO, 0, NULL);
 	ifmedia_set(&sc->sc_media, IFM_ETHER | IFM_AUTO);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_gif.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_gif.c,v
diff -u -p -r1.135 if_gif.c
--- sys/net/if_gif.c	22 Dec 2023 23:01:50 -0000	1.135
+++ sys/net/if_gif.c	23 Dec 2023 10:27:51 -0000
@@ -176,6 +176,7 @@ gif_clone_create(struct if_clone *ifc, i
 
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
+	if_counters_alloc(ifp);
 
 #if NBPFILTER > 0
 	bpfattach(&ifp->if_bpf, ifp, DLT_LOOP, sizeof(uint32_t));
Index: sys/net/if_gre.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_gre.c,v
diff -u -p -r1.177 if_gre.c
--- sys/net/if_gre.c	22 Dec 2023 23:01:50 -0000	1.177
+++ sys/net/if_gre.c	23 Dec 2023 10:27:51 -0000
@@ -592,6 +592,7 @@ gre_clone_create(struct if_clone *ifc, i
 	timeout_set_proc(&sc->sc_ka_hold, gre_keepalive_hold, sc);
 	sc->sc_ka_state = GRE_KA_NONE;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
@@ -658,6 +659,7 @@ mgre_clone_create(struct if_clone *ifc, 
 	sc->sc_tunnel.t_df = htons(0);
 	sc->sc_tunnel.t_ecn = ECN_ALLOWED;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
@@ -714,6 +716,7 @@ egre_clone_create(struct if_clone *ifc, 
 	ifmedia_add(&sc->sc_media, IFM_ETHER | IFM_AUTO, 0, NULL);
 	ifmedia_set(&sc->sc_media, IFM_ETHER | IFM_AUTO);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
@@ -791,6 +794,7 @@ nvgre_clone_create(struct if_clone *ifc,
 	ifmedia_add(&sc->sc_media, IFM_ETHER | IFM_AUTO, 0, NULL);
 	ifmedia_set(&sc->sc_media, IFM_ETHER | IFM_AUTO);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
@@ -854,6 +858,7 @@ eoip_clone_create(struct if_clone *ifc, 
 	ifmedia_add(&sc->sc_media, IFM_ETHER | IFM_AUTO, 0, NULL);
 	ifmedia_set(&sc->sc_media, IFM_ETHER | IFM_AUTO);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_mpe.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_mpe.c,v
diff -u -p -r1.103 if_mpe.c
--- sys/net/if_mpe.c	22 Dec 2023 23:01:50 -0000	1.103
+++ sys/net/if_mpe.c	23 Dec 2023 10:27:51 -0000
@@ -119,6 +119,7 @@ mpe_clone_create(struct if_clone *ifc, i
 
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
+	if_counters_alloc(ifp);
 
 #if NBPFILTER > 0
 	bpfattach(&ifp->if_bpf, ifp, DLT_LOOP, sizeof(u_int32_t));
Index: sys/net/if_mpip.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_mpip.c,v
diff -u -p -r1.17 if_mpip.c
--- sys/net/if_mpip.c	22 Dec 2023 23:01:50 -0000	1.17
+++ sys/net/if_mpip.c	23 Dec 2023 10:27:51 -0000
@@ -121,6 +121,7 @@ mpip_clone_create(struct if_clone *ifc, 
 	ifp->if_hardmtu = 65535;
 
 	if_attach(ifp);
+	if_counters_alloc(ifp);
 	if_alloc_sadl(ifp);
 
 #if NBPFILTER > 0
Index: sys/net/if_mpw.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_mpw.c,v
diff -u -p -r1.64 if_mpw.c
--- sys/net/if_mpw.c	22 Dec 2023 23:01:50 -0000	1.64
+++ sys/net/if_mpw.c	23 Dec 2023 10:27:51 -0000
@@ -115,6 +115,7 @@ mpw_clone_create(struct if_clone *ifc, i
 
 	sc->sc_dead = 0;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_pflow.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_pflow.c,v
diff -u -p -r1.108 if_pflow.c
--- sys/net/if_pflow.c	22 Dec 2023 23:01:50 -0000	1.108
+++ sys/net/if_pflow.c	23 Dec 2023 10:27:51 -0000
@@ -279,6 +279,7 @@ pflow_clone_create(struct if_clone *ifc,
 
 	task_set(&pflowif->sc_outputtask, pflow_output_process, pflowif);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
Index: sys/net/if_pfsync.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_pfsync.c,v
diff -u -p -r1.323 if_pfsync.c
--- sys/net/if_pfsync.c	22 Dec 2023 23:01:50 -0000	1.323
+++ sys/net/if_pfsync.c	23 Dec 2023 10:27:51 -0000
@@ -444,6 +444,7 @@ pfsync_clone_create(struct if_clone *ifc
 #endif
 	}
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
Index: sys/net/if_pppx.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_pppx.c,v
diff -u -p -r1.127 if_pppx.c
--- sys/net/if_pppx.c	22 Dec 2023 23:01:50 -0000	1.127
+++ sys/net/if_pppx.c	23 Dec 2023 10:27:51 -0000
@@ -684,6 +684,7 @@ pppx_add_session(struct pppx_dev *pxd, s
 	ifp->if_type = IFT_PPP;
 	ifp->if_softc = pxi;
 	/* ifp->if_rdomain = req->pr_rdomain; */
+	if_counters_alloc(ifp);
 
 	if_attach(ifp);
 
@@ -1079,6 +1080,7 @@ pppacopen(dev_t dev, int flags, int mode
 	ifp->if_qstart = pppac_qstart;
 	ifp->if_ioctl = pppac_ioctl;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
Index: sys/net/if_sec.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_sec.c,v
diff -u -p -r1.8 if_sec.c
--- sys/net/if_sec.c	22 Dec 2023 23:01:50 -0000	1.8
+++ sys/net/if_sec.c	23 Dec 2023 10:27:51 -0000
@@ -147,6 +147,7 @@ sec_clone_create(struct if_clone *ifc, i
 	ifp->if_ioctl = sec_ioctl;
 	ifp->if_rtrequest = p2p_rtrequest;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
Index: sys/net/if_tpmr.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_tpmr.c,v
diff -u -p -r1.34 if_tpmr.c
--- sys/net/if_tpmr.c	22 Dec 2023 23:01:50 -0000	1.34
+++ sys/net/if_tpmr.c	23 Dec 2023 10:27:51 -0000
@@ -168,6 +168,7 @@ tpmr_clone_create(struct if_clone *ifc, 
 	ifp->if_xflags = IFXF_CLONED | IFXF_MPSAFE;
 	ifp->if_link_state = LINK_STATE_DOWN;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
 
Index: sys/net/if_trunk.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_trunk.c,v
diff -u -p -r1.153 if_trunk.c
--- sys/net/if_trunk.c	22 Dec 2023 23:01:50 -0000	1.153
+++ sys/net/if_trunk.c	23 Dec 2023 10:27:51 -0000
@@ -193,6 +193,7 @@ trunk_clone_create(struct if_clone *ifc,
 	 * Attach as an ordinary ethernet device, children will be attached
 	 * as special device IFT_IEEE8023ADLAG.
 	 */
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_tun.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_tun.c,v
diff -u -p -r1.239 if_tun.c
--- sys/net/if_tun.c	22 Dec 2023 23:01:50 -0000	1.239
+++ sys/net/if_tun.c	23 Dec 2023 10:27:51 -0000
@@ -246,6 +246,8 @@ tun_create(struct if_clone *ifc, int uni
 	ifp->if_hardmtu = TUNMRU;
 	ifp->if_link_state = LINK_STATE_DOWN;
 
+	if_counters_alloc(ifp);
+
 	if ((flags & TUN_LAYER2) == 0) {
 #if NBPFILTER > 0
 		ifp->if_bpf_mtap = bpf_mtap;
Index: sys/net/if_var.h
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_var.h,v
diff -u -p -r1.131 if_var.h
--- sys/net/if_var.h	22 Dec 2023 23:01:50 -0000	1.131
+++ sys/net/if_var.h	23 Dec 2023 10:27:51 -0000
@@ -379,6 +379,9 @@ int	if_rxr_info_ioctl(struct if_rxrinfo 
 int	if_rxr_ioctl(struct if_rxrinfo *, const char *, u_int,
 	    struct if_rxring *);
 
+void	if_counters_alloc(struct ifnet *);
+void	if_counters_free(struct ifnet *);
+
 int	if_txhprio_l2_check(int);
 int	if_txhprio_l3_check(int);
 int	if_rxhprio_l2_check(int);
Index: sys/net/if_veb.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_veb.c,v
diff -u -p -r1.33 if_veb.c
--- sys/net/if_veb.c	22 Dec 2023 23:01:50 -0000	1.33
+++ sys/net/if_veb.c	23 Dec 2023 10:27:51 -0000
@@ -314,6 +314,7 @@ veb_clone_create(struct if_clone *ifc, i
 	ifp->if_flags = IFF_BROADCAST | IFF_SIMPLEX | IFF_MULTICAST;
 	ifp->if_xflags = IFXF_CLONED | IFXF_MPSAFE;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 
 	if_alloc_sadl(ifp);
@@ -2347,6 +2348,7 @@ vport_clone_create(struct if_clone *ifc,
 	ifp->if_xflags = IFXF_CLONED | IFXF_MPSAFE;
 	ether_fakeaddr(ifp);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_vlan.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_vlan.c,v
diff -u -p -r1.217 if_vlan.c
--- sys/net/if_vlan.c	22 Dec 2023 23:01:50 -0000	1.217
+++ sys/net/if_vlan.c	23 Dec 2023 10:27:51 -0000
@@ -215,6 +215,7 @@ vlan_clone_create(struct if_clone *ifc, 
 	ifp->if_hardmtu = 0xffff;
 	ifp->if_link_state = LINK_STATE_DOWN;
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 	ifp->if_hdrlen = EVL_ENCAPLEN;
Index: sys/net/if_vxlan.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_vxlan.c,v
diff -u -p -r1.98 if_vxlan.c
--- sys/net/if_vxlan.c	22 Dec 2023 23:01:50 -0000	1.98
+++ sys/net/if_vxlan.c	23 Dec 2023 10:27:51 -0000
@@ -275,6 +275,7 @@ vxlan_clone_create(struct if_clone *ifc,
 	ifp->if_xflags = IFXF_CLONED | IFXF_MPSAFE;
 	ether_fakeaddr(ifp);
 
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 
Index: sys/net/if_wg.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/net/if_wg.c,v
diff -u -p -r1.33 if_wg.c
--- sys/net/if_wg.c	22 Dec 2023 23:01:50 -0000	1.33
+++ sys/net/if_wg.c	23 Dec 2023 10:27:51 -0000
@@ -2693,6 +2693,7 @@ wg_clone_create(struct if_clone *ifc, in
 
 	if_attach(ifp);
 	if_alloc_sadl(ifp);
+	if_counters_alloc(ifp);
 
 #if NBPFILTER > 0
 	bpfattach(&ifp->if_bpf, ifp, DLT_LOOP, sizeof(uint32_t));
Index: sys/netinet/ip_carp.c
===================================================================
RCS file: /data/mirror/openbsd/cvs/src/sys/netinet/ip_carp.c,v
diff -u -p -r1.359 ip_carp.c
--- sys/netinet/ip_carp.c	22 Dec 2023 23:01:50 -0000	1.359
+++ sys/netinet/ip_carp.c	23 Dec 2023 10:27:51 -0000
@@ -831,6 +831,7 @@ carp_clone_create(struct if_clone *ifc, 
 	ifp->if_start = carp_start;
 	ifp->if_enqueue = carp_enqueue;
 	ifp->if_xflags = IFXF_CLONED;
+	if_counters_alloc(ifp);
 	if_attach(ifp);
 	ether_ifattach(ifp);
 	ifp->if_type = IFT_CARP;
PATCH
}

#### Subs ####

sub quirks {
    my ($before, $after);
    $before = str2time($_[0])
	or croak "Could not parse date '$_[0]'"
	if $_[0];
    $after = str2time($_[1])
	or croak "Could not parse date '$_[1]'"
	if $_[1];

    my %q;
    while (my($k, $v) = each %quirks) {
	my $commit = $v->{commit} ||= str2time($k)
	    or die "Invalid commit date '$k'";
	next if $before && $commit <= $before;
	next if $after && $commit > $after;
	$v->{date} = strftime("%FT%TZ", gmtime($commit));
	$q{$commit} = $v;
    }
    return %q;
}

sub quirk_patches {
    my %q = quirks(@_);
    return
	'makefile-linkalign' => patch_makefile_linkalign(),
	'makefile-norandom' => patch_makefile_norandom(),
	'makegap-norandom'  => patch_makegap_norandom(),
	map { %{$q{$_}{patches} || {}} } sort keys %q;
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
	    push @c, "cd /usr/src && patch -NuF0 -p0 <$file";
	}
	foreach my $cmd (@{$v->{prebuildcommands} || []}) {
	    push @c, "cd /usr/src && $cmd";
	}
	foreach my $dir (@{$v->{cleandirs} || []}) {
	    push @c, "cd /usr/src && make -C $dir clean";
	}
	foreach my $dir (@{$v->{builddirs} || []}) {
	    my $ncpu = $sysctl->{'hw.ncpuonline'};
	    push @c, "cd /usr/src && make -C $dir obj";
	    push @c, "cd /usr/src && nice make -C $dir -j $ncpu all";
	    push @c, "cd /usr/src && make -C $dir install";
	}
	foreach my $cmd (@{$v->{buildcommands} || []}) {
	    push @c, "cd /usr/src && $cmd";
	}
	foreach my $cmd (@{$v->{commands} || []}) {
	    push @c, $cmd;
	}
    }

    return @c;
}

sub quirk_releases {
    my %q = quirks();
    my %r;
    my $prev;
    foreach my $commit (sort keys %q) {
	my $release = $q{$commit}{release}
	    or next;
	my $date = strftime("%FT%TZ", gmtime($commit));
	(my $before = $date) =~ s/T.*Z/T00:00:00Z/;
	my $after = strftime("%FT%TZ", gmtime($commit + 24*60*60 - 1));
	$after =~ s/T.*Z/T00:00:00Z/;
	$prev->{end} = $after if $prev;
	$prev = $r{$release} = {
	    date => $date,
	    begin => $before,
	}
    }
    return %r;
}

sub quirk_index2letters {
    my ($index) = @_;
    my $ord = $index % 52;  # A-Z, a-z is 2 * 26 chars
    $ord += $ord < 26 ? ord('A') : ord('a') - 26;
    return chr($ord) . ("'" x ($index / 52));
}

1;
