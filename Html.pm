# put common html printing functions in a module

# Copyright (c) 2018-2021 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2018-2019 Moritz Buhl <mbuhl@genua.de>
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

package Html;

use strict;
use warnings;
use Carp;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);

use Buildquirks;

use parent 'Exporter';
our @EXPORT= qw(
    html_open
    html_close
    html_header
    html_footer
    html_navigate
    html_status_table
    html_quirks_table
    parse_version_file
    status2severity
    log2status
    html_running_table
);

# create new html file, return handle and file name
sub html_open {
    my ($path) = @_;
    my $htmlfile = "$path.html";
    unlink("$htmlfile.new");
    open(my $html, '>', "$htmlfile.new")
	or croak "Open '$htmlfile.new' for writing failed: $!";
    return wantarray ? ($html, $htmlfile) : $html;
}

# close new html file, rename atomically, create gzipped copy
sub html_close {
    my ($html, $htmlfile, $nozip) = @_;
    close($html)
	or croak "Close '$htmlfile.new' after writing failed: $!";
    rename("$htmlfile.new", "$htmlfile")
	or croak "Rename '$htmlfile.new' to '$htmlfile' failed: $!";
    return if $nozip;
    system("gzip -f -c $htmlfile >$htmlfile.gz.new")
	and croak "Gzip '$htmlfile' failed: $?";
    rename("$htmlfile.gz.new", "$htmlfile.gz")
	or croak "Rename '$htmlfile.gz.new' to '$htmlfile.gz' failed: $!";
}
# open html page, print head, open body
sub html_header {
    my ($html, $title, $headline, @nav) = @_;
    print $html <<"HEADER";
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <title>$title</title>
  <link rel="icon" href="/favicon.svg">
  <style>
    th { text-align: left; white-space: nowrap; }
    th.desc { text-align: left; white-space: nowrap; }
    th.test { text-align: left; white-space: nowrap; }
    td.test { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0;}
    tr.IMG {background-color: #ffffff;}
    td.PASS {background-color: #80ff80;}
    td.XFAIL {background-color: #80ffc0;}
    td.SKIP {background-color: #8080ff;}
    td.XPASS {background-color: #ff80c0;}
    td.FAIL {background-color: #ff8080;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.status, td.status a {color: black;}
    td.outlier {color: red;}
    iframe {width: 100%; border: none; min-height: 1200px;}
  </style>
</head>

<body>
HEADER
    html_navigate($html, @nav) if @nav;
    print $html "<h1>$headline</h1>\n";
}

# close html body and page
sub html_footer {
    my ($html) = @_;
    print $html <<"FOOTER";
</body>
</html>
FOOTER
}

# insert navigation links
sub html_navigate {
    my ($html, @nav) = @_;
    while (my $text = shift @nav) {
	my $id = lc($text);
	my $link = shift @nav;
	my $href = $link ? " href=\"$link\"" : "";
	print $html "  <a id=\"$id\"$href>$text</a>\n";
    }
}

my %badstatus;
sub status2severity {
    my $status = shift;
    my $severity =
	$status eq 'PASS'    ?  1 :
	$status eq 'XFAIL'   ?  2 :
	$status eq 'SKIP'    ?  3 :
	$status eq 'XPASS'   ?  4 :
	$status eq 'FAIL'    ?  5 :
	$status eq 'NOEXIT'  ?  6 :
	$status eq 'NOTERM'  ?  7 :
	$status eq 'NORUN'   ?  8 :
	$status eq 'NOLOG'   ?  9 :
	$status eq 'NOCLEAN' ? 10 :
	$status eq 'NOEXIST' ? 11 : 12;
    if ($severity == 12 && ! $badstatus{$status}) {
	$badstatus{$status} = 1;
	warn "unknown status '$status'\n";
    }
    return $severity;
}

# print html table explaining the status of regress or perform results
sub html_status_table {
    my ($html, $type) = @_;
    my ($topic, $tool);
    ($topic, $tool) = ("make regress", "make") if $type eq "regress";
    ($topic, $tool) = ("performance test", "test") if $type eq "perform";
    ($topic, $tool) = ("make test", "make") if $type eq "portstest";
    ($topic, $tool) = ("make release", "make") if $type eq "release";
    ($topic, $tool) = ("netlink test", "test") if $type eq "netlink";
    print $html <<"TABLE";
<table>
  <tr>
    <td class="status PASS">PASS</td>
    <td>$topic passed</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "regress";
  <tr>
    <td class="status FAIL">FAIL</td>
    <td>$topic failed, string FAILED in test output</td>
  </tr>
  <tr>
    <td class="status XFAIL">XFAIL</td>
    <td>$topic passed, string EXPECTED_FAIL in test output</td>
  </tr>
  <tr>
    <td class="status XPASS">XPASS</td>
    <td>$topic failed, string UNEXPECTED_PASS in test output</td>
  </tr>
  <tr>
    <td class="status SKIP">SKIP</td>
    <td>$topic skipped itself, string SKIPPED in test output</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "perform";
  <tr>
    <td class="status FAIL">FAIL</td>
    <td>$topic failed to produce value</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "portstest";
  <tr>
    <td class="status FAIL">FAIL</td>
    <td>$topic failed</td>
  </tr>
  <tr>
    <td class="status SKIP">SKIP</td>
    <td>make fetch failed, test skipped</td>
  </tr>
  <tr>
    <td class="status NOEXIT">NOEXIT</td>
    <td>make build failed, cannot test</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type =~ /^(regress|perform|release)$/;
  <tr>
    <td class="status NOEXIT">NOEXIT</td>
    <td>$topic did not exit with code 0, $tool failed</td>
  </tr>
TABLE
    print $html <<"TABLE";
  <tr>
    <td class="status NOTERM">NOTERM</td>
    <td>$tool did not terminate, aborted after timeout</td>
  </tr>
  <tr>
    <td class="status NORUN">NORUN</td>
    <td>$tool did not run, execute failed</td>
  </tr>
  <tr>
    <td class="status NOLOG">NOLOG</td>
    <td>create log file for $tool output failed</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "regress" || $type eq "portstest";
  <tr>
    <td class="status NOCLEAN">NOCLEAN</td>
    <td>make clean before running test failed</td>
  </tr>
  <tr>
    <td class="status NOEXIST">NOEXIST</td>
    <td>test directory not found</td>
  </tr>
TABLE
    print $html <<"TABLE";
</table>
TABLE
}

# print html table explaining the letters of the build quirks
sub html_quirks_table {
    my ($html) = @_;
    my %q = quirks();
    my @sorted_quirks = sort keys %q;
    print $html "<table>\n";
    for my $index (0 .. $#sorted_quirks) {
	my $quirkdate = $sorted_quirks[$index];
	my $letter = quirk_index2letters($index);
	print $html <<"ROW";
  <tr>
    <td>$q{$quirkdate}{date}</td>
    <th>$letter</th>
    <td>$q{$quirkdate}{comment}</td>
  </tr>
ROW
    }
    print $html "</table>\n";
}

# extract status from log file
sub log2status {
    my ($logfile) = @_;

    open(my $fh, '<', $logfile)
	or return 'NOEXIST';

    defined(my $line = <$fh>)
	or return 'NOLOG';
    $line =~ /^Script .* started/i
	or return 'NORUN';

    # if seek from end fails, file is too short, then read from the beginning
    seek($fh, 0, SEEK_SET);
    seek($fh, -1000, SEEK_END);
    # reread file buffer at current position, ignore error or end of file
    readline($fh);
    # find final line
    while (<$fh>) {
	$line = $_;
    }

    $line =~ /^Warning:/
	and return 'NOTERM';
    $line =~ /^[A-Z].* failed/
	and return 'FAIL';
    $line =~ /^Script .* finished/i
	and return 'PASS';
    return 'NOEXIT';
}

# return hash with kernel cvs time short arch core
sub parse_version_file {
    my ($version) = @_;

    open(my $fh, '<', $version)
	or croak "Open '$version' for reading failed: $!";
    my %v;
    while (<$fh>) {
	my @kern = /^kern.version=(.*(?:cvs : (\w+))?: ((\w+ \w+ +\d+) .*))$/;
	if (@kern) {
	    @v{qw(kernel kerncvs kerntime kernshort)} = @kern;
	    if (<$fh> =~ /(\S+)/) {
		$v{kernel} .= "\n    $1";
		$v{location} = $1;
	    }
	}
	/^hw.machine=(\w+)$/ and $v{arch} = $1;
	/^hw.ncpu=(\w+)$/ and $v{ncpu} = $1;
    }
    return %v;
}

# print html table explaining the running status
sub html_running_table {
    my ($html) = @_;
    print $html <<"TABLE";
<table>
  <tr>
    <td class="status PASS">PASS</td>
    <td>finished successfully</td>
  </tr>
  <tr>
    <td class="status FAIL">FAIL</td>
    <td>finished with failure</td>
  </tr>
  <tr>
    <td class="status NOEXIT">NOEXIT</td>
    <td>in progress</td>
  </tr>
</table>
TABLE
}

1;
