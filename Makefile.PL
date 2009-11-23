use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'HTML::Laundry',
    AUTHOR        => 'Six Apart, Ltd. <scook@sixapart.com>',
    VERSION_FROM  => 'lib/HTML/Laundry.pm',
    ABSTRACT_FROM => 'lib/HTML/Laundry.pm',
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ( 'LICENSE' => 'perl' )
        : () ),
    PL_FILES  => {},
    PREREQ_PM => {
        'Test::More'      => 0,
        'Test::Exception' => 0,
        'HTML::Entities'  => 0,
        'HTML::Parser'    => 0,
        'Scalar::Util'    => 0,
        'Switch'          => 0,
        'URI'             => 0,
        'URI::Escape'     => 0,
        'URI::Split'      => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'HTML-Laundry-*' },
);
