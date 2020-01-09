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
    html_table_status
    html_table_quirks
);

# print html table explaining the status of test results
sub html_table_status {
    print $html <<"TABLE";
<table>
  <tr>
    <th>PASS</th>
    <td>make regress passed</td>
  </tr>
  <tr>
    <th>FAIL</th>
    <td>make regress failed, string FAILED in test output</td>
  </tr>
  <tr>
    <th>XFAIL</th>
    <td>make regress passed, string EXPECTED_FAIL in test output</td>
  </tr>
  <tr>
    <th>XPASS</th>
    <td>make regress failed, string UNEXPECTED_PASS in test output</td>
  </tr>
  <tr>
    <th>SKIP</th>
    <td>make regress skipped itself, string SKIPPED in test output</td>
  </tr>
  <tr>
    <th>NOEXIT</th>
    <td>make regress did not exit with code 0, make failed</td>
  </tr>
  <tr>
    <th>NOTERM</th>
    <td>make regress did not terminate, aborted after timeout</td>
  </tr>
  <tr>
    <th>NORUN</th>
    <td>make regress did not run, execute make failed</td>
  </tr>
  <tr>
    <th>NOLOG</th>
    <td>create log file for make output failed</td>
  </tr>
  <tr>
    <th>NOCLEAN</th>
    <td>make clean before running test failed</td>
  </tr>
  <tr>
    <th>NOEXIST</th>
    <td>test directory not found</td>
  </tr>
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
