#!/usr/bin/perl
# convert all test results to a html table

use strict;
use warnings;
use Cwd;
use File::Basename;
use HTML::Entities;
use POSIX;
use URI::Escape;

my $now = strftime("%FT%TZ", gmtime);

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

my @results = sort glob("*/test.result");

my (%t, %d);
foreach my $result (@results) {
    my ($date, $short) = $result =~ m,((.+)T.+)/test.result,;
    $d{$date} = {
	short => $short,
	result => $result,
    };
    $d{$date}{setup} = "$date/setup.html" if -f "$date/setup.html";
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

open(my $html, '>', "regress.html")
    or die "Open 'regress.html' for writing failed: $!";
print $html "<!DOCTYPE html>\n";
print $html "<html>\n";
print $html "<head>\n";
print $html "  <title>OpenBSD Regress Results</title>\n";
print $html "</head>\n";

print $html "<body>\n";
print $html "<h1>OpenBSD regress tests</h1>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>created at</th>\n";
print $html "    <td>$now</td>\n";
print $html "  </tr>\n";
print $html "  <tr>\n    <th>test</th>\n";
print $html "    <td><a href=\"run.html\">run</a></td>\n";
print $html "  </tr>\n";
print $html "</table>\n";
print $html "<table>\n";
my @dates = reverse sort keys %d;
print $html "  <tr>\n    <th>test at date</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $setup = $d{$date}{setup};
    $setup = join("/", map { uri_escape($_) } split("/", $setup)) if $setup;
    my $time = encode_entities($date);
    my $href = $setup ? "<a href=\"$setup\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$time\">$href$short$enda</th>\n";
}
print $html "  </tr>\n";

my @tests = sort { $t{$b}{severity} <=> $t{$a}{severity} || $a cmp $b }
    keys %t;
foreach my $test (@tests) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	my $message = encode_entities($t{$test}{$date}{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $logfile = uri_escape($t{$test}{$date}{logfile});
	my $href = $logfile ? "<a href=\"$logfile\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <td$title>$href$status$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>PASS</th>\n";
print $html "    <td>make regress passed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>FAIL</th>\n";
print $html "    <td>make regress failed, ";
print $html "string FAILED in test output</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOEXIT</th>\n";
print $html "    <td>make regress did not exit with code 0, ";
print $html "make failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOTERM</th>\n";
print $html "    <td>make regress did not terminate, ";
print $html "aborted after timeout</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NORUN</th>\n";
print $html "    <td>make regress did not run, ";
print $html "execute make failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOLOG</th>\n";
print $html "    <td>create log file for make output failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOCLEAN</th>\n";
print $html "    <td>make clean before running test failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOEXIST</th>\n";
print $html "    <td>test directory not found</td>\n  </tr>\n";
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close 'regress.html' after writing failed: $!";
