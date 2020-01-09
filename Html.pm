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
    html_table_quirks
);

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
