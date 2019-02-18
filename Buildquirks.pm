# get build over incompatible source changes with minimal effort

# Copyright (c) 2018-2019 Alexander Bluhm <bluhm@genua.de>
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
our @EXPORT= qw(quirks quirk_comments quirk_patches quirk_commands);

#### Quirks ####

my %quirks = (
# OpenBSD 6.2, 2017-10-04Z
    '2017-10-04T03:27:49Z' => { comment => "OpenBSD/amd64 6.2 release" },
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
# OpenBSD 6.3, 2018-03-24Z
    '2018-03-24T20:27:40Z' => { comment => "OpenBSD/amd64 6.3 release" },
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
# OpenBSD 6.4, 2018-10-11Z
    '2018-10-11T19:37:31Z' => { comment => "OpenBSD/amd64 6.4 release" },
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
);

#### Patches ####

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
