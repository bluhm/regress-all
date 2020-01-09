# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
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

use Buildquirks;

use parent 'Exporter';
our @EXPORT= qw(
    html_header
    html_footer
    html_table_status
    html_table_quirks
    status2severity
);

# open html page, print head, open body
sub html_header {
    my ($html, $title, $headline) = @_;
    print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>$title</title>
  <style>
    th { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
    td.PASS {background-color: #80ff80;}
    td.XFAIL {background-color: #80ffc0;}
    td.SKIP {background-color: #8080ff;}
    td.XPASS {background-color: #ff80c0;}
    td.FAIL {background-color: #ff8080;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
    td.outlier {color: red;}
    iframe {width: 100%; border: none; min-height: 1200px;}
  </style>
</head>

<body>
<h1>$headline</h1>
HEADER
}

# close html body and page
sub html_footer {
    my ($html) = @_;
    print $html <<"FOOTER";
</body>
</html>
FOOTER
}

%badstatus;
sub status2severity {
    my $status = shift;
    my $severity =
	$status eq 'PASS'   ? 1 :
	$status eq 'XFAIL'  ? 2 :
	$status eq 'SKIP'   ? 3 :
	$status eq 'XPASS'  ? 4 :
	$status eq 'FAIL'   ? 5 :
	$status eq 'NOEXIT' ? 6 :
	$status eq 'NOTERM' ? 7 :
	$status eq 'NORUN'  ? 8 : 10;
    if ($severity == 10 && ! $badstatus{$status}) {
	$badstatus{$status} = 1;
	warn "unknown status '$status'\n";
    }
    return $severity;
}

# print html table explaining the status of regress or perform results
sub html_table_status {
    my ($html, $type) = @_;
    my ($topic, $tool);
    ($topic, $tool) = ("make regress", "make") if $type eq "regress";
    ($topic, $tool) = ("performance test", "test") if $type eq "perform";
    print $html <<"TABLE";
<table>
  <tr>
    <th>PASS</th>
    <td>$topic passed</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "regress";
  <tr>
    <th>FAIL</th>
    <td>$topic failed, string FAILED in test output</td>
  </tr>
  <tr>
    <th>XFAIL</th>
    <td>$topic passed, string EXPECTED_FAIL in test output</td>
  </tr>
  <tr>
    <th>XPASS</th>
    <td>$topic failed, string UNEXPECTED_PASS in test output</td>
  </tr>
  <tr>
    <th>SKIP</th>
    <td>$topic skipped itself, string SKIPPED in test output</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "perform";
  <tr>
    <th>FAIL</th>
    <td>$topic failed to produce value</td>
  </tr>
TABLE
    print $html <<"TABLE";
  <tr>
    <th>NOEXIT</th>
    <td>$topic did not exit with code 0, $tool failed</td>
  </tr>
  <tr>
    <th>NOTERM</th>
    <td>$topic did not terminate, aborted after timeout</td>
  </tr>
  <tr>
    <th>NORUN</th>
    <td>$topic did not run, execute $tool failed</td>
  </tr>
  <tr>
    <th>NOLOG</th>
    <td>create log file for $tool output failed</td>
  </tr>
TABLE
    print $html <<"TABLE" if $type eq "regress";
  <tr>
    <th>NOCLEAN</th>
    <td>make clean before running test failed</td>
  </tr>
  <tr>
    <th>NOEXIST</th>
    <td>test directory not found</td>
  </tr>
TABLE
    print $html <<"TABLE";
</table>
TABLE
}

# print html table explaining the letters of the build quirks
sub html_table_quirks {
    my ($html) = @_;
    my %q = quirks();
    my @sorted_quirks = sort keys %q;
    print $html "<table>";
    for my $qi (0 .. $#sorted_quirks) {
	my $letter = chr(($qi > 25? $qi + 6 : $qi) + 65);
	print $html "<tr>";
	print $html "<th>$letter</th><td>$q{$sorted_quirks[$qi]}{comment}</td>";
	print $html "</tr>";
    }
    print $html "</table>";
}

1;