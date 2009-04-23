use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;

require_ok('HTML::Laundry');
my $tidy_available;
eval {
	require HTML::Tidy;
	$tidy_available = 1;
};

SKIP: {
	skip 'HTML::Tidy unavailable; skipping tidy tests', 15 unless ( $tidy_available );
    my $l1 = HTML::Laundry->new();
    my $plaintext = 'She was the youngest of the two daughters of a most affectionate, indulgent father...';
    is( $l1->clean($plaintext), $plaintext, 'Short plain text passes through cleanly');
    $plaintext = q{She had been a friend and companion such as few possessed: intelligent, well-informed, useful, gentle, knowing all the ways of the family, interested in all its concerns, and peculiarly interested in herself, in every pleasure, every scheme of hers--one to whom she could speak every thought as it arose, and who had such an affection for her as could never find fault.};
    is( $l1->clean($plaintext), $plaintext, 'Longer plain text passes through cleanly');
    my $kurosawa = q[Akira Kurosawa (Kyūjitai: 黒澤 明, Shinjitai: 黒沢 明 Kurosawa Akira, 23 March 1910 – 6 September 1998) was a legendary Japanese filmmaker, producer, screenwriter and editor];
    is( $l1->clean($kurosawa), $kurosawa, 'UTF-8 text passes through cleanly');
    my $valid = q{<p>} . $plaintext . q{</p>};
    is( $l1->clean($valid), $valid, 'Validating HTML passes through cleanly');
    TODO: {
        local $TODO = "libtidy version dependent - figure out how to check";
        is( $l1->clean('<div></div>'), q{}, 'No-content elements are stripped...');
        is( $l1->clean('<div foo="bar"></div>'), q{<div id="foo"></div>}, '...unless they have attributes');
        my $para = q{<p>Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>};
        is( $l1->clean($para), $para, q{Single-quotes are preserved} );
    }
    is( $l1->clean('<p></p>'), '<p></p>', 'Non-empty tag passes through cleanly');
    is( $l1->clean('<br />'), '<br />', 'Empty tag passes through cleanly');
    is( $l1->clean('<br /   >'), '<br />', 'Empty tag with whitespace passes through cleanly');
    is( $l1->clean('<p />'), '<p></p>', 'Non-empty tag passed in as empty is normalized to non-empty format');
    is( $l1->clean('<br></br>'), '<br />', 'Empty tag passed in as non-empty is normalized to empty format');
    is( $l1->clean('<br class="foo" />'), '<br class="foo" />', 'Empty tag attribute is preserved');
    is( $l1->clean('<p class="foo"></p>'), '<p class="foo"></p>', 'Non-empty tag attribute is preserved');
    # Actual tidying begins
    is( $l1->clean('<em><strong>Important!'), '<em><strong>Important!</strong></em>', 'Unclosed tags are closed');
    is( $l1->clean('<p><strong>Important!</p></strong>'), '<p><strong>Important!</strong></p>', 'Transposed close tags are fixed');
    is( $l1->clean('<p>P1</p><p>P2</p>'), "<p>P1</p>\n<p>P2</p>", 'Line breaks are inserted between block tags');
    is( $l1->clean('<li>Buy milk</li><li>Pick up dry cleaning</li>'), "<ul>\n<li>Buy milk</li>\n<li>Pick up dry cleaning</li>\n</ul>", 'Naked <li> tags are given <ul> wrapper');
}


