require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;

WriteMakefile (
 NAME		=> "Thread::Conveyor",
 ($[ >= 5.005) ?
 (AUTHOR	=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
  ABSTRACT	=> 'transport of any data-structure') : (),
 VERSION_FROM	=> 'lib/Thread/Conveyor.pm',
 PREREQ_PM	=> {
                    'Thread::Tie' => '0.07',
                   },
);
