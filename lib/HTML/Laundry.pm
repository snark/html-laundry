########################################################
# Copyright © 2009 Six Apart, Ltd.

package HTML::Laundry;

use strict;
use warnings;

use 5.008;
use version; our $VERSION = 0.0001;

=head1 NAME

HTML::Laundry - Perl module to clean HTML by the piece

=head1 VERSION

Version 0.0001

=head1 SYNOPSIS

    #!/usr/bin/perl -w
    use strict;
    use HTML::Laundry;
    my $laundry = HTML::Laundry->new();
    my $snippet = q{
        <P STYLE="font-size: 300%"><BLINK>"You may get to touch her<BR>
        If your gloves are sterilized<BR></BR>
        Rinse your mouth with Listerine</BR>
        Blow disinfectant in her eyes"</BLINK><BR>
        -- X-Ray Spex, <I>Germ-Free Adolescents<I>
        <SCRIPT>alert('!!');</SCRIPT>
    };
    my $germfree = $laundry->clean($snippet);
    # $germfree is now:
    #   <p>&quot;You may get to touch her<br />
    #   If your gloves are sterilized<br />
    #   Rinse your mouth with Listerine<br />
    #   Blow disinfectant in her eyes&quot;<br />
    #   -- X-Ray Spex, <i>Germ-Free Adolescents</i></p>
        
=head1 DESCRIPTION

C<HTML::Laundry> is an L<HTML::Parser|HTML::Parser>-based HTML normalizer, 
meant for small pieces of HTML, such as user comments, Atom feed entries,
and the like, rather than full pages. Laundry takes these and returns clean,
sanitary, UTF-8-based XHTML.

A snippet is cleaned several ways:

=over 4

=item * Normalized, using HTML::Parser: attributes and elements will be
lowercased, empty elements such as <img /> and <br /> will be forced into
the empty tag syntax if needed, and unknown attributes and elements will be
stripped

=item * Sanitized, using an extensible whitelist of valid attributes and 
elements based on Mark Pilgrim and Aaron Swartz's work on C<sanitize.py>: tags
and attributes which are known to be possible attack vectors are removed

=item * Tidied, using L<HTML::Tidy|HTML::Tidy> (as available): unclosed tags
will be closed and the output generally neatened; future version may also use
HTML::Tidy to deal with character encoding issues

=item * Optionally rebased, to turn relative URLs in attributes into
absolute ones

=back

C<HTML::Laundry> provides mechanisms to extend the list of known allowed 
(and disallowed) tags, along with callback methods to allow scripts using
C<HTML::Laundry> to extend the behavior in various ways. Future versions
will provide additional options for altering the rules used to clean 
snippets.

C<HTML::Laundry> doesn't know about the <head> attributes of HTML pages
and probably never will. L<HTML::Scrubber|HTML::Scrubber> is a better tool 
for sanitizing full HTML pages.

=cut

require HTML::Laundry::Rules;

require HTML::Parser;
use HTML::Entities qw(encode_entities encode_entities_numeric);
use URI;
use Switch;

my @fragments;
my $unacceptable_count;
my $local_unacceptable_count;
my $cdata_dirty;
my $in_cdata;
my $tag_leading_whitespace = qr/
    (?<=<)  # Left bracket followed by
    \s*     # any amount of whitespace
    (\/?)   # optionally with a forward slash
    \s*     # and then more whitespace
/x;

=head1 FUNCTIONS

=head2 new

Create an HTML::Laundry object.

    my $tidy = HTML::Laundry->new();

Takes an optional anonymous hash of arguments:

=over 4

=item * base_url

This turns relative URIs, as in <img src="surly_otter.png">, into 
absolute URIs, as for use in feed parsing.

    my $l = HTML::Laundry->new({ base_uri => 'http://example.com/foo/' });
    

=item * notidy

Disable use of HTML::Tidy, even if it's available on your system.

    my $l = HTML::Laundry->new({ notidy => 1 });
    
=back

The list of flags and syntax for using them may change.

=cut

sub new {
    my $class = shift;
    my $args  = shift;
    my $self  = {};
    $self->{tidy}              = undef;
    $self->{tidy_added_inline} = {};
    $self->{tidy_added_empty}  = {};
    bless $self, $class;
    $self->unset_callback('start_tag');
    $self->unset_callback('end_tag');
    $self->unset_callback('text');
    $self->unset_callback('output');
    $self->{parser} = HTML::Parser->new(
        api_version => 3,
        start_h => [ sub { $self->_tag_start_handler(@_) }, 'tagname,attr' ],
        end_h  => [ sub { $self->_tag_end_handler(@_) }, 'tagname,attr' ],
        text_h => [ sub { $self->_text_handler(@_) },    'dtext,is_cdata' ],
        empty_element_tags => 1,
        marked_sections    => 1,
    );
    $self->{cdata_parser} = HTML::Parser->new(
        api_version => 3,
        start_h => [ sub { $self->_tag_start_handler(@_) }, 'tagname,attr' ],
        end_h  => [ sub { $self->_tag_end_handler(@_) }, 'tagname,attr' ],
        text_h => [ sub { $self->_text_handler(@_) },    'dtext' ],
        empty_element_tags => 1,
        unbroken_text      => 1,
        marked_sections    => 0,
    );
    $self->initialize($args);

    if ( !$args->{notidy} ) {
        $self->_generate_tidy;
    }
    return $self;
}

=head2 initialize

Instantiates HTML::Laundry object properties based on the
C<HTML::Laundry::Rules> module.

=cut

sub initialize {
    my ( $self, $args ) = @_;

    # Set defaults
    $self->{tidy_added_tags}          = undef;
    $self->{tidy_empty_tags}          = undef;
    $self->{trim_trailing_whitespace} = 1;
    $self->{trim_tag_whitespace}      = 0;
    $self->{base_uri}                 = $args->{base_uri};

    my $rules = new HTML::Laundry::Rules;
    $self->{ruleset} = $rules;

    # Initialize based on ruleset
    $self->{acceptable_a}   = $rules->acceptable_a();
    $self->{acceptable_e}   = $rules->acceptable_e();
    $self->{empty_e}        = $rules->empty_e();
    $self->{unacceptable_e} = $rules->unacceptable_e();
    $self->{rebase_list}    = $rules->rebase_list();
    return;
}

=head2 set_callback

Set a callback of type "start_tag", "end_tag", "text", or "output".

    $l->set_callback('start_tag', sub {
        my ($laundry, $tagref, $attrhashref) = @_;
        # Now, perform actions
    });

=cut

sub set_callback {
    my ( $self, $action, $ref ) = @_;
    return if ( ref($ref) ne 'CODE' );
    switch ($action) {
        case q{start_tag} {
            $self->{start_tag_callback} = $ref;
        }
        case q{end_tag} {
            $self->{end_tag_callback} = $ref;
        }
        case q{text} {
            $self->{text_callback} = $ref;
        }
        case q{output} {
            $self->{output_callback} = $ref;
        }
    }
    return;
}

=head2 unset_callback

Removes a callback of type "start_tag", "end_tag", "text", or "output".

    $l->unset_callback('start_tag');

=cut

sub unset_callback {
    my ( $self, $action ) = @_;
    switch ($action) {
        case q{start_tag} {
            $self->{start_tag_callback} = sub { return 1; };
        }
        case q{end_tag} {
            $self->{end_tag_callback} = sub { return 1; };
        }
        case q{text} {
            $self->{text_callback} = sub { return 1; };
        }
        case q{output} {
            $self->{output_callback} = sub { return 1; };
        }
    }
    return;
}

=head2 clean

Cleans a snippet of HTML, using the ruleset and object creation options given
to the Laundry object. The snippet should be passed as a scalar.

    $output1 =  $l->clean( '<p>The X-rays were penetrating' );
    $output2 =  $l->clean( $snippet );

=cut

sub clean {
    my ( $self, $chunk, $args ) = @_;
    $self->_reset_state();
    if ( $self->{trim_tag_whitespace} ) {
        $chunk =~ s/$tag_leading_whitespace/$1/gs;
    }
    my $p  = $self->{parser};
    my $cp = $self->{cdata_parser};
    $p->parse($chunk);
    if ( !$in_cdata && !$unacceptable_count ) {
        $p->eof();
    }
    if ( $in_cdata && !$local_unacceptable_count ) {
        $cp->eof();
    }
    my $output = $self->gen_output;
    $cp->eof();    # Clear buffer if we haven't already
    if ($cdata_dirty) {    # Overkill to get out of CDATA parser state
        $self->{parser} = HTML::Parser->new(
            api_version => 3,
            start_h =>
                [ sub { $self->_tag_start_handler(@_) }, 'tagname,attr' ],
            end_h => [ sub { $self->_tag_end_handler(@_) }, 'tagname,attr' ],
            text_h => [ sub { $self->_text_handler(@_) }, 'dtext,is_cdata' ],
            empty_element_tags => 1,
            marked_sections    => 1,
        );
    }
    else {
        $p->eof();         # Clear buffer if we haven't already
    }
    return $output;
}

=head2 gen_output

Used to generate the final, XHTML output from the internal stack of text and 
tag tokens. Generally meant to be used internally, but potentially useful for
callbacks that wish to get a snapshot of what the output would look like at
some point during the cleaning process.

    my $xhtml = $l->gen_output;

=cut

sub gen_output {
    my $self = shift;
    if ( !$self->{output_callback}->( $self, \@fragments ) ) {
        return q{};
    }
    my $output = join '', @fragments;
    if ( $self->{tidy} ) {
        $output = $self->{tidy}->clean($output);
        $self->{tidy}->clear_messages;
    }
    if ( $self->{trim_trailing_whitespace} ) {
        $output =~ s/\s+$//;
    }
    return $output;
}

=head2 empty_elements

Returns a list of the Laundry object's known empty elements: elements such
as <img /> or <br /> which must not contain any children.

=cut

sub empty_elements {
    my ( $self, $listref ) = @_;
    if ($listref) {
        my @list = @{$listref};
        my %empty = map { ( $_, 1 ) } @list;
        $self->{empty_e} = \%empty;
    }
    return keys %{ $self->{empty_e} };
}

=head2 remove_empty_element

Remove an element (or, if given an array reference, multiple elements) from
the "empty elements" list maintained by the Laundry object.

    $l->remove_empty_element(['img', 'br']); # Let's break XHTL!
    
This will not affect the acceptable/unacceptable status of the elements.

=cut

sub remove_empty_element {
    my ( $self, $new_e, $args ) = @_;
    my $empty = $self->{empty_e};
    if ( ref($new_e) eq 'ARRAY' ) {
        foreach my $e (@{$new_e}) {
            $self->remove_empty_element( $e, $args );
        }
    }
    else {
        delete $empty->{$new_e};
    }
    return 1;
}

=head2 acceptable_elements

Returns a list of the Laundry object's known acceptable elements, which will
not be stripped during the sanitizing process.

=cut

sub acceptable_elements {
    my ( $self, $listref ) = @_;
    if ( ref($listref) eq 'ARRAY' ) {
        my @list = @{$listref};
        my %acceptable = map { ( $_, 1 ) } @list;
        $self->{acceptable_e} = \%acceptable;
    }
    return keys %{ $self->{acceptable_e} };
}

=head2 add_acceptable_element

Add an element (or, if given an array reference, multiple elements) to the
"acceptable elements" list maintained by the Laundry object. Items added in
this manner will automatically be removed from the "unacceptable elements"
list if they are present.

    $l->add_acceptable_element('style');

Elements which are empty may be flagged as such with an optional argument.
If this flag is set, all elements provided by the call will be added to
the "empty element" list.

    $l->add_acceptable_element(['applet', 'script'], { empty => 1 });

=cut

sub add_acceptable_element {
    my ( $self, $new_e, $args ) = @_;
    my $acceptable   = $self->{acceptable_e};
    my $empty        = $self->{empty_e};
    my $unacceptable = $self->{unacceptable_e};
    if ( ref($new_e) eq 'ARRAY' ) {
        foreach my $e ( @{$new_e} ) {
            $self->add_acceptable_element( $e, $args );
        }
    }
    else {
        $acceptable->{$new_e} = 1;
        if ( $args->{empty} ) {
            $empty->{$new_e} = 1;
            if ( $self->{tidy} ) {
                $self->{tidy_added_inline}->{$new_e} = 1;
                $self->{tidy_added_empty}->{$new_e}  = 1;
                $self->_generate_tidy;
            }
        }
        elsif ( $self->{tidy} ) {
            $self->{tidy_added_inline}->{$new_e} = 1;
            $self->_generate_tidy;
        }
        delete $unacceptable->{$new_e};

    }
    return 1;
}

=head2 remove_acceptable_element

Remove an element (or, if given an array reference, multiple elements) to the
"acceptable elements" list maintained by the Laundry object. These items 
(although not their child elements) will now be stripped during parsing.

    $l->remove_acceptable_element(['img', 'h1', 'h2']);
    $l->clean(q{<h1>The Day the World Turned Day-Glo</h1>});
    # returns 'The Day the World Turned Day-Glo'

=cut

sub remove_acceptable_element {
    my ( $self, $new_e, $args ) = @_;
    my $acceptable = $self->{acceptable_e};
    if ( ref($new_e) eq 'ARRAY' ) {
        foreach my $e (@{$new_e}) {
            $self->remove_acceptable_element( $e, $args );
        }
    }
    else {
        delete $acceptable->{$new_e};
    }
    return 1;
}

=head2 unacceptable_elements

Returns a list of the Laundry object's unacceptable elements, which will be 
stripped -- B<including> child objects -- during the cleaning process.

=cut

sub unacceptable_elements {
    my ( $self, $listref ) = @_;
    if ( ref($listref) eq 'ARRAY' ) {
        my @list = @{$listref};
        my %unacceptable
            = map { $self->remove_acceptable_element($_); ( $_, 1 ); } @list;
        $self->{unacceptable_e} = \%unacceptable;
    }
    return keys %{ $self->{unacceptable_e} };
}

=head2 add_unacceptable_element

Add an element (or, if given an array reference, multiple elements) to the
"unacceptable elements" list maintained by the Laundry object.

    $l->add_unacceptable_element(['h1', 'h2']);
    $l->clean(q{<h1>The Day the World Turned Day-Glo</h1>});
    # returns null string

=cut

sub add_unacceptable_element {
    my ( $self, $new_e, $args ) = @_;
    my $unacceptable = $self->{unacceptable_e};
    if ( ref($new_e) eq 'ARRAY' ) {
        foreach my $e ( @{$new_e} ) {
            $self->add_unacceptable_element( $e, $args );
        }
    }
    else {
        $self->remove_acceptable_element($new_e);
        $unacceptable->{$new_e} = 1;
    }
    return 1;
}

=head2 remove_unacceptable_element

Removes an element (or, if given an array reference, multiple elements) from 
the "unacceptable elements" list maintained by the Laundry object. Note that
this does not automatically add the element to the acceptable_element list.

    $l->clean(q{<script>alert('!')</script>});
    # returns null string
    $l->remove_unacceptable_element( q{script} );
    $l->clean(q{<script>alert('!')</script>});
    # returns "alert('!')"

=cut

sub remove_unacceptable_element {
    my ( $self, $new_e, $args ) = @_;
    my $unacceptable = $self->{unacceptable_e};
    if ( ref($new_e) eq 'ARRAY' ) {
        foreach my $a (@{$new_e}) {
            $self->remove_unacceptable_element( $a, $args );
        }
    }
    else {
        delete $unacceptable->{$new_e};
    }
    return 1;
}

=head2 acceptable_attributes

Returns a list of the Laundry object's known acceptable attributes, which will
not be stripped during the sanitizing process.

=cut

sub acceptable_attributes {
    my ( $self, $listref ) = @_;
    if ( ref($listref) eq 'ARRAY' ) {
        my @list = @{$listref};
        my %acceptable = map { ( $_, 1 ) } @list;
        $self->{acceptable_a} = \%acceptable;
    }
    return keys %{ $self->{acceptable_a} };
}

=head2 add_acceptable_attribute

Add an attribute (or, if given an array reference, multiple attributes) to the
"acceptable attributes" list maintained by the Laundry object.

    my $snippet = q{ <p austen:id="3">"My dear Mr. Bennet," said his lady to 
        him one day, "have you heard that <span austen:footnote="netherfield">
        Netherfield Park</span> is let at last?"</p>
    };
    $l->clean( $snippet );
    # returns:
    #   <p>&quot;My dear Mr. Bennet,&quot; said his lady to him one day, 
    #   &quot;have you heard that <span>Netherfield Park</span> is let at 
    #   last?&quot;</p>
    $l->add_acceptable_attribute([austen:id, austen:footnote]);
    $l->clean( $snippet );
    # returns:
    #   <p austen:id="3">&quot;My dear Mr. Bennet,&quot; said his lady to him
    #   one day, &quot;have you heard that <span austen:footnote="netherfield">
    #   Netherfield Park</span> is let at last?&quot;</span></p>
    
=cut

sub add_acceptable_attribute {
    my ( $self, $new_a, $args ) = @_;
    my $acceptable = $self->{acceptable_a};
    if ( ref($new_a) eq 'ARRAY' ) {
        foreach my $a ( @{$new_a} ) {
            $self->add_acceptable_attribute( $a, $args );
        }
    }
    else {
        $acceptable->{$new_a} = 1;
    }
    return 1;
}

=head2 remove_acceptable_attribute

Removes an attribute (or, if given an array reference, multiple attributes)
from the "acceptable attributes" list maintained by the Laundry object.

    $l->clean(q{<p id="plugh">plover</p>});
    # returns '<p id="plugh">plover</p>'
    $l->remove_acceptable_element( q{id} );
    $l->clean(q{<p id="plugh">plover</p>});
    # returns '<p>plover</p>

=cut

sub remove_acceptable_attribute {
    my ( $self, $new_a, $args ) = @_;
    my $acceptable = $self->{acceptable_a};
    if ( ref($new_a) eq 'ARRAY' ) {
        foreach my $a (@{$new_a}) {
            $self->remove_acceptable_attribute( $a, $args );
        }
    }
    else {
        delete $acceptable->{$new_a};
    }
    return 1;
}

=head2 _generate_tidy

Private method used to set up the class's HTML::Tidy instance

=cut

sub _generate_tidy {
    my $self = shift;
    eval {
        require HTML::Tidy;
        $self->{tidy_ruleset} = $self->{ruleset}->tidy_ruleset;
        if ( keys %{ $self->{tidy_added_inline} } ) {
            $self->{tidy_ruleset}->{new_inline_tags}
                = join( q{,}, keys %{ $self->{tidy_added_inline} } );
        }
        if ( keys %{ $self->{tidy_added_empty} } ) {
            $self->{tidy_ruleset}->{new_empty_tags}
                = join( q{,}, keys %{ $self->{tidy_added_empty} } );
        }
        $self->{tidy} = HTML::Tidy->new( $self->{tidy_ruleset} );
        1;
    };
    return;
}

=head2 _reset_state

Private method used to clear out lingering data

=cut

sub _reset_state {
    my ($self) = @_;
    @fragments                = ();
    $unacceptable_count       = 0;
    $local_unacceptable_count = 0;
    $in_cdata                 = 0;
    $cdata_dirty              = 0;
    return;
}

=head2 _tag_start_handler

Private method used by the class's HTML::Parser objects

=cut

sub _tag_start_handler {
    my ( $self, $tagname, $attr ) = @_;
    if ( !$self->{start_tag_callback}->( $self, \$tagname, $attr ) ) {
        return;
    }
    if ( !$in_cdata ) {
        $cdata_dirty = 0;
    }
    my @attributes;
    my $check_rebase;
    if ( $self->{base_uri}
        && grep {/^$tagname$/} keys %{ $self->{rebase_list} } )
    {
        $check_rebase = 1;
    }
    foreach my $k ( keys %{$attr} ) {
        if ( $self->{acceptable_a}->{$k} ) {
            if ( $check_rebase && grep {/^$k$/}
                @{ $self->{rebase_list}->{$tagname} } )
            {
                my $uri = URI->new_abs( $attr->{$k}, $self->{base_uri} );
                $attr->{$k} = $uri->as_string;
            }
            push @attributes, $k . q{="} . $attr->{$k} . q{"};
        }
    }
    my $attributes = join q{ }, @attributes;
    if ( $self->{acceptable_e}->{$tagname} ) {
        if ( $self->{empty_e}->{$tagname} ) {
            if ($attributes) {
                $attributes = $attributes . q{ };
            }
            push @fragments, "<$tagname $attributes/>";
        }
        else {
            if ($attributes) {
                $attributes = q{ } . $attributes;
            }
            push @fragments, "<$tagname$attributes>";
        }
    }
    else {
        if ( $self->{unacceptable_e}->{$tagname} ) {
            if ($in_cdata) {
                $local_unacceptable_count += 1;
            }
            else {
                $unacceptable_count += 1;
            }
        }
    }
    return;
}

=head2 _tag_end_handler

Private method used by the class's HTML::Parser objects

=cut

sub _tag_end_handler {
    my ( $self, $tagname ) = @_;
    if ( !$self->{end_tag_callback}->( $self, \$tagname ) ) {
        return;
    }
    if ( !$in_cdata ) {
        $cdata_dirty = 0;
    }
    if ( $self->{acceptable_e}->{$tagname} ) {
        if ( !$self->{empty_e}->{$tagname} ) {
            push @fragments, "</$tagname>";
        }
    }
    else {
        if ( $self->{unacceptable_e}->{$tagname} ) {
            if ($in_cdata) {
                $local_unacceptable_count -= 1;
                $local_unacceptable_count = 0
                    if ( $local_unacceptable_count < 0 );
            }
            else {
                $unacceptable_count -= 1;
                $unacceptable_count = 0 if ( $unacceptable_count < 0 );
            }
        }
    }
    return;
}

=head2 _tag_text_handler

Private method used by the class's HTML::Parser objects

=cut

sub _text_handler {
    my ( $self, $text, $is_cdata ) = @_;
    if ( $in_cdata && $local_unacceptable_count ) {
        return;
    }
    if ($unacceptable_count) {
        return;
    }
    if ($is_cdata) {
        my $cp = $self->{cdata_parser};
        $in_cdata = 1;
        $cp->parse($text);
        if ( !$local_unacceptable_count ) {
            $cp->eof();
        }
        $cdata_dirty = 1;
        $in_cdata    = 0;
        return;
    }
    else {
        if ( !$self->{text_callback}->( $self, \$text, $is_cdata ) ) {
            return q{};
        }
        $text = encode_entities( $text, '<>&"' );
        $cdata_dirty = 0;
    }
    push @fragments, $text;
    return;
}

=head1 AUTHOR

Steve Cook, C<< <scook at sixapart.com> >>

=head1 BUGS

Please report any bugs or feature requests on the GitHub page for this project.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HTML::Laundry

=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Six Apart, Ltd., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1;    # End of HTML::Laundry
