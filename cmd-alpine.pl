#!/usr/bin/perl

use strict;
use warnings;

print "\nupdate and upgrade\n";

my @cmd = qw(apk update);
system(@cmd)
    and die "Command '@cmd' failed: $?";
@cmd = qw(apk upgrade);
system(@cmd)
    and die "Command '@cmd' failed: $?";

print "\ninstall packages\n";

@cmd = qw(xargs apk add);
my $list = "pkg-alpine.list";
open(my $in, '<', $list)
    or die "Open file '$list' for reading failed: $!";
open(my $out, '|-', @cmd)
    or die "Open pipe to command '@cmd' failed: $!";
while(<$in>) {
    print $out $_;
}
close($out) or die $! ?
    "Close pipe to command '@cmd' failed: $!" :
    "Command '@cmd' failed: $?";

print "\nadd user\n";

my @users = qw(tcpbench iperf3);
foreach my $user (@users) {
    @cmd = (qw(adduser -SDH), $user);
    system(@cmd) && $? != 256
	and die "Command '@cmd' failed: $?";
}

print "\ncreate openrc script\n";

my %rcscript;
$rcscript{tcpbench} = <<'EOF';
#!/sbin/openrc-run

description="TCP benchmarking and measurement tool"
supervisor="supervise-daemon"
command="/usr/local/bin/tcpbench"
command_args="-s"
command_user="tcpbench"

depend() {
        need net
        after firewall
}
EOF
$rcscript{iperf3} = <<'EOF';
#!/sbin/openrc-run

description="Perform network throughput tests"
command="/usr/bin/iperf3"
command_args="-sD"
command_user="iperf3"

depend() {
        need net
        after firewall
}
EOF

my @services = qw(tcpbench iperf3);
foreach my $service (@services) {
    my $openrc = "/etc/init.d/$service";
    open(my $fh, '>', $openrc)
	or die "Open file '$openrc' for writing failed: $!";
    chmod 0755, $fh
	or die "Chmod file '$openrc' failed: $!";
    print $fh $rcscript{$service};
    close($fh)
	or die "Close file '$openrc' after writing failed: $!";
}

print "\nactivate and start service\n";

foreach my $service (@services) {
    @cmd = (qw(rc-update add), $service);
    system(@cmd)
	and die "Command '@cmd' failed: $?";
    @cmd = ('rc-service', $service, 'restart');
    system(@cmd)
	and die "Command '@cmd' failed: $?";
}
@cmd = ('openrc');
system(@cmd)
    and die "Command '@cmd' failed: $?";

exit;
