#!/usr/bin/perl
# convert all tst results to a html table

use strict;
use warnings;
use POSIX;

my $now = strftime("%FT%TZ", gmtime);

my @results = sort glob("results/*/test.result");

my (%t, %d);
foreach my $result (@results) {
    my ($date) = $result =~ m,results/(.+)/test.result,;
    $d{$date} = 1;
    open(my $fh, '<', $result)
	or die "Open '$result' for reading failed: $!";
    while (<$fh>) {
	my ($status, $test, $message) = split(" ", $_, 3);
	my $severity =
	    $status eq 'PASS' ? 1 :
	    $status eq 'FAIL' ? 2 :
	    $status eq 'NOEXIT' ? 3 :
	    $status eq 'NOTERM' ? 4 : 5;
	$t{$test}{$date}
	    and warn "Duplicate test '$test' at date '$date'";
	$t{$test}{$date} = {
	    status => $status,
	    message => $message,
	};
	$t{$test}{severity} = ($t{$test}{severity} || 0) * .5 + $severity;
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
print $html "  <tr>\n    <th>test at date</th>\n",
    (map { "    <th>$_</th>\n" } @dates), "  </tr>\n";
foreach my $test (sort { $t{$a}{severity} <=> $t{$b}{severity} } keys %t) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	print $html "    <td>$status</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close 'test.html' after writing failed: $!";
