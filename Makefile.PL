require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;
eval "use Devel::Required";

WriteMakefile (
 NAME		=> "Thread::Conveyor",
 AUTHOR		=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
 ABSTRACT	=> 'transport of any data-structure',
 VERSION_FROM	=> 'lib/Thread/Conveyor.pm',
 PREREQ_PM	=> {
                    'load'        => 0,
                    'Thread::Tie' => '0.09',
                   },
);
