#!/usr/bin/perl
# convert all tst results to a html table

use strict;
use warnings;
use File::Basename;
use POSIX;

my $now = strftime("%FT%TZ", gmtime);

my @results = sort glob("results/*/test.result");

my (%t, %d);
foreach my $result (@results) {
    my ($date, $short) = $result =~ m,results/((.+)T.+)/test.result,;
    $d{$date} = {
	short => $short,
	result => $result,
    };
    $_->{severity} *= .5 foreach values %t;
    open(my $fh, '<', $result)
	or die "Open '$result' for reading failed: $!";
    while (<$fh>) {
	my ($status, $test, $message) = split(" ", $_, 3);
	$t{$test}{$date}
	    and warn "Duplicate test '$test' at date '$date'";
	$t{$test}{$date} = {
	    status => $status,
	    message => $message,
	};
	my $severity =
	    $status eq 'PASS' ? 1 :
	    $status eq 'FAIL' ? 2 :
	    $status eq 'NOEXIT' ? 3 :
	    $status eq 'NOTERM' ? 4 : 5;
	$t{$test}{severity} += $severity;
	my $logfile = dirname($result). "/logs/$test/make.log";
	$t{$test}{$date}{logfile} = $logfile if -f $logfile;
    }
    close($fh)
	or die "Close '$result' after reading failed: $!";
}

open(my $html, '>', "test.html")
    or die "Open 'test.html' for writing failed: $!";
print $html "<!DOCTYPE html>\n";
print $html "<html>\n";
print $html "<head>\n";
print $html "  <title>OpenBSD Regress Tests</title>\n";
print $html "</head>\n";

print $html "<body>\n";
print $html "<h1>OpenBSD regress results at $now</h1>\n";
print $html "<table>\n";
my @dates = reverse sort keys %d;
print $html "  <tr>\n    <th>test at date</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $result = $d{$date}{result};
    print $html "    <th><a href=\"$result\">$short</a></th>\n";
}
print $html "  </tr>\n";

my @tests = sort { $t{$b}{severity} <=> $t{$a}{severity} || $a cmp $b }
    keys %t;
foreach my $test (@tests) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	my $message = $t{$test}{$date}{message};
	my $title = $message ? " title=\"$message\"" : "";
	my $logfile = $t{$test}{$date}{logfile};
	my $href = $logfile ? "<a href=\"$logfile\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <td$title>$href$status$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close 'test.html' after writing failed: $!";
