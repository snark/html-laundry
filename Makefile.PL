use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'HTML::Laundry',
    AUTHOR              => 'Six Apart, Ltd. <scook@sixapart.com>',
    VERSION_FROM        => 'lib/HTML/Laundry.pm',
    ABSTRACT_FROM       => 'lib/HTML/Laundry.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'HTML-Laundry-*' },
);
