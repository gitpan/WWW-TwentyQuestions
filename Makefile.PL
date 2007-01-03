use 5.008008;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'WWW::TwentyQuestions',
    VERSION_FROM      => 'lib/WWW/TwentyQuestions.pm',
    PREREQ_PM         => {},
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/WWW/TwentyQuestions.pm',
       AUTHOR         => 'Casey James <casey--at--cuvou.net') : ()),
);
