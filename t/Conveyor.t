BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use Test::More tests => 17 + (3*4);

BEGIN { use_ok('Thread::Conveyor') }

my $belt = Thread::Conveyor->new;
isa_ok( $belt, 'Thread::Conveyor', 'check object type' );
can_ok( $belt,qw(
 maxboxes
 minboxes
 new
 onbelt
 peek
 peek_dontwait
 put
 take
 take_dontwait
) );

$belt->put( qw(a b c) );
$belt->put( [qw(a b c)] );
$belt->put( {a => 1, b => 2, c => 3} );

is( $belt->onbelt, 3,			'check number boxes on belt');

my @l = $belt->take;
is( @l, 3,				'check # elements simple list' );
ok( $l[0] eq 'a' and $l[1] eq 'b' and $l[2] eq 'c', 'check simple list' );

my @lr = $belt->take_dontwait;
cmp_ok( @lr, '==', 1,			'check # elements list ref' );
is( ref($lr[0]), 'ARRAY',		'check type of list ref' );
ok(
 $lr[0]->[0] eq 'a' and $lr[0]->[1] eq 'b' and $lr[0]->[2] eq 'c',
 'check list ref'
);

my @hr = $belt->peek_dontwait;
cmp_ok( @hr, '==', 1,			'check # elements hash ref, #1' );
is( ref($hr[0]), 'HASH',		'check type of hash ref, #1' );

my @hr = $belt->peek;
cmp_ok( @hr, '==', 1,			'check # elements hash ref, #2' );
is( ref($hr[0]), 'HASH',		'check type of hash ref, #2' );

@hr = $belt->take;
cmp_ok( @hr, '==', 1,			'check # elements hash ref, #3' );
is( ref($hr[0]), 'HASH',		'check type of hash ref, #3' );
ok(
 $hr[0]->{a} == 1 and $hr[0]->{b} == 2 and $hr[0]->{c} == 3,
 'check hash ref'
);

my @e = $belt->take_dontwait;
cmp_ok( @e, '==', 0,			'check # elements dontwait' );

foreach ({maxboxes => undef},{},{maxboxes => 500, minboxes => 495}) {
  my $belt = Thread::Conveyor->new( $_ );
  isa_ok( $belt,'Thread::Conveyor',	'check object type' );
  my @n : shared;
  my $thread = threads->new(
   sub {
     while (1) {
       my ($n) = $belt->take;
       return unless defined( $n );
       push( @n,$n );
     }
   }
  );
  isa_ok( $thread,'threads',		'check object type' );
  $belt->put( $_ ) foreach 1..1000,undef;
  ok( !defined( $thread->join ),	'check result of join()' );
  my $check = '';
  $check .= $_ foreach 1..1000;
  is( join('',@n),$check,		'check result of boxes on belt' );
}
