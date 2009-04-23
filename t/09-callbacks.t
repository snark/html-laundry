use strict;
use warnings;

use Test::More tests => 26;

require_ok('HTML::Laundry');

my $l = HTML::Laundry->new({ notidy => 1 });

my $start_count = 0;
my $end_count = 0;
my $text_count = 0;
my $output_count = 0;

sub start_test {
    my ( $laundry, $tagref, $attrref ) = @_;
    my $tag = ${$tagref};
    isa_ok( $laundry, 'HTML::Laundry', 'Laundry object is passed into start_tag callback' );
    is($tag, q{p}, 'Tag is passed correctly to start_tag callback');
    is($attrref->{id}, q{foo}, 'Attribute (id) is passed correctly via start_tag callback');
    is($attrref->{class}, q{bar}, 'Attribute (class) is passed correctly via start_tag callback');
    $attrref->{class} = q{baz};
    delete $attrref->{id};
    my $newtag = q{span};
    ${$tagref} = $newtag;
    return 1;
}

sub end_test {
    my ( $laundry, $tagref, $attrref ) = @_;
    my $tag = ${$tagref};
    isa_ok( $laundry, 'HTML::Laundry', 'Laundry object is passed into end_tag callback' );
    is($tag, q{p}, 'Tag is passed correctly to end_tag callback');
    ok( ! $attrref, 'Attributes not passed to end_tag callback');
    my $newtag = q{span};
    ${$tagref} = $newtag;
    return 1;
}

sub text_test {
    my ( $laundry, $textref, $iscdata ) = @_;
    isa_ok( $laundry, 'HTML::Laundry', 'Laundry object is passed into text callback' );
    my $text = ${$textref};
    my $expected = q{Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.};
    is($text, $expected, 'Text is passed correctly to text callback');
    ${$textref} = 'The family of Dashwood had been long settled in Sussex.';
    return 1;
}

sub entity_test {
    my ( $laundry, $textref, $iscdata ) = @_;
    my $text = ${$textref};
    ok($text !~ q{lt;}, 'Text is passed before entity escaping has occured');
    return 1;
}

sub output_test {
    my ( $laundry, $fragsref ) = @_;
    isa_ok( $laundry, 'HTML::Laundry', 'Laundry object is passed into output callback' );
    my @fragments = @{$fragsref};
    is(scalar @fragments, 3, 'Fragments array is passed via reference, has right number of elements');
    @{$fragsref} = ('<p>', 'The family of Dashwood had been long settled', ' in Sussex.', '</p>');
    return 1;
}

sub cancel {
    return 0;
}

my $austen = q{<p id="foo" class="bar">Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>};
my $alt_austen = q{<p class="bar" id="foo">Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>};
my $output;

$l->set_callback('start_tag', \&start_test );
$output = $l->clean( $austen );
is( $output,
    q{<span class="baz">Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>},
    'Start tag callback allows: elimination of attribute; modification of attribute; modification of tag'
);
$l->set_callback('start_tag', \&cancel );
$output = $l->clean( $austen );
is( $output,
    q{Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>},
    'Start tag callback allows forced non-parsing of tag via false return'
);
$l->unset_callback('start_tag');
$output = $l->clean($austen);
ok( ($output eq $austen or $output eq $alt_austen), 'Unset start_tag callback turns off callback');

$l->set_callback('end_tag', \&end_test );
$austen = q{<p id="foo">Sixteen years had Miss Taylor been in Mr. Woodhouse's family, less as a governess than a friend, very fond of both daughters, but particularly of Emma.</p>};
$output = $l->clean($austen);
$austen =~ s{/p}{/span};
ok( ($output eq $austen), 'end_tag callback allows modification of end tag');
$austen =~ s{/span}{/p};
$l->set_callback('end_tag', \&cancel );
$output = $l->clean($austen);
$output .= q{</p>};
ok( ($output eq $austen), 'end_tag callback allows forced non-parsing of end tag via false return');
$l->unset_callback('end_tag');
$output = $l->clean($austen);
ok( ($output eq $austen), 'Unset end_tag callback turns off callback');
$l->set_callback('text', \&text_test );
$output = $l->clean($austen);
is($output, q{<p id="foo">The family of Dashwood had been long settled in Sussex.</p>}, 'Text callback allows manipulation of text');
$l->set_callback('text', \&entity_test );
$l->clean(q{1 < 2});
$l->set_callback('text', \&cancel );
$output = $l->clean($austen);
is( $output, q{<p id="foo"></p>}, 'Text callback allows forced non-parsing of text via false return ');
$l->unset_callback('text');
$output = $l->clean($austen);
is( $output, $austen, 'Unset text callback turns off callback');
$l->set_callback('output', \&output_test );
$output = $l->clean($austen);
is( $output, q{<p>The family of Dashwood had been long settled in Sussex.</p>}, 'Output callback allows manipulation of entire output stack');
$l->unset_callback('output');
$output = $l->clean($austen);
is( $output, $austen, 'Unset output callback turns off callback');
