use strict;
use warnings;

use Test::More tests => 21;

require_ok('HTML::Laundry');

my $l = HTML::Laundry->new({ notidy => 1 });

note 'Clean URLs';

is( $l->clean(q{<IMG SRC="http://example.com/otter.png">}), q{<img src="http://example.com/otter.png" />}, 'Legit <img> not affected');
is( $l->clean(q{<IMG SRC="mypath/otter.png">}), q{<img src="mypath/otter.png" />}, 'Legit <img> with relative URL not affected');
is( $l->clean(q{<IMG SRC=file:///home/smoot/of_ute.jpg>}), q{<img />}, 'Legitimate URL with unsupported scheme is cleaned away');
TODO: {
    local $TODO = q{Haven't added in use of Net::LibIDN or Net::DNS::IDNA yet};
    is( $l->clean(q{<A  HREF="http://π.cr.yp.to/" />}), q{<a href="http://xn--1xa.cr.yp.to/"></a>}, '<a href> with UTF-8 domain name is Punycode escaped');
}
is( $l->clean(q{<A  HREF="http://ja.wikipedia.org/wiki/メインページ"></a>}), q{<a href="http://ja.wikipedia.org/wiki/%E3%A1%E3%A4%E3%B3%E3%E3%BC%E3%B8"></a>}, '<a href> with UTF-8 path is escaped');

note 'Begin nastiness';
# based on http://ha.ckers.org/xss.html#XSScalc
is( $l->clean(q{<IMG SRC="javascript:alert('XSS');">}), q{<img />}, 'Unobfuscated <img> is neutralized');
is( $l->clean(q{<IMG SRC=javascript:alert('XSS')>}), q{<img />}, '<img> with no quotes or semicolon is neutralized');
is( $l->clean(q{<IMG SRC=JaVaScRiPt:alert('XSS')>}), q{<img />}, '<img> with case-varying is neutralized');
is( $l->clean(q{<IMG SRC=javascript:alert(&quot;XSS&quot;)>}), q{<img />}, '<img> with HTML entities is neutralized');
is( $l->clean(q{<IMG SRC=`javascript:alert("RSnake says, 'XSS'")`>}), q{<img />}, '<img> with grave accents is neutralized');
is( $l->clean(q{<IMG """><SCRIPT>alert("XSS")</SCRIPT>">}), q{<img />&quot;&gt;}, 'malformed <img> with scripts is neutralized');
is( $l->clean(q{<IMG SRC=javascript:alert(String.fromCharCode(88,83,83))>}), q{<img />}, '<img> with fromCharCode is neutralized');
is( $l->clean(q{<IMG SRC=&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>}), q{<img />}, '<img> UTF-8 encoding is neutralized');
is( $l->clean(q{<IMG SRC=&#0000106&#0000097&#0000118&#0000097&#0000115&#0000099&#0000114&#0000105&#0000112&#0000116&#0000058&#0000097&#0000108&#0000101&#0000114&#0000116&#0000040&#0000039&#0000088&#0000083&#0000083&#0000039&#0000041>}),
    '<img />', '<img> with long-style UTF-8 encoding is neutralized');
is( $l->clean(q{<IMG SRC=&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29>}),
    q{<img />}, '<img> with no-colon hex encoding is neutralized');
is( $l->clean(q{<IMG SRC="jav	ascript:alert('XSS');">}), q{<img />}, '<img> with embedded tab is neutralized');
is( $l->clean(q{<IMG SRC="jav&#x09;ascript:alert('XSS');">}), q{<img />}, '<img> with encoded embedded tab is neutralized');
is( $l->clean(q{<IMG SRC="jav&#x0A;ascript:alert('XSS');">}), q{<img />}, '<img> with encoded embedded newline is neutralized');
is( $l->clean(q{<IMG SRC="jav&#x0D;ascript:alert('XSS');">}), q{<img />}, '<img> with encoded embedded CR is neutralized');
is( $l->clean(q{<IMG
SRC
=
"
j
a
v
a
s
c
r
i
p
t
:
a
l
e
r
t
(
'
X
S
S
'
)
"
>
}), q{<img />}, '<img> with multiline JS is neutralized');

# http://imfo.ru/csstest/css_hacks/import.php