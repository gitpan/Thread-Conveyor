package Thread::Conveyor;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.03';
use strict;

# Make sure we have threads
# Make sure we can share and wait and signal
# Make sure we have Storable
# Make sure we can throttle if needed

use threads ();
use threads::shared qw(cond_wait cond_signal cond_broadcast);
use Storable ();
use Thread::Conveyor::Throttled ();

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# Class methods

#---------------------------------------------------------------------------
#  IN: 1 class with which to bless the object
#      2 parameter hash reference
# OUT: 1 instantiated object

sub new {

# Obtain the class
# Obtain the parameter hash, or create an empty one
# Create the conveyor belt
# And bless it as a local object

    my $class = shift;
    my $self = shift || {};
    my @belt : shared;
    my $belt = bless \@belt,$class;

# Set the default number of boxes to throttle to unless specifically specified
# Return now with a simple unthrottled belt if so explicitely specified

    $self->{'maxboxes'} = 50 unless exists( $self->{'maxboxes'} );
    return $belt unless $self->{'maxboxes'};

# Set the minimum number of boxes if not set yet
# Embed the bare belt object in the throttled object
# Initialize a shared halted flag
# Safe a reference to it in the object

    $self->{'minboxes'} ||= $self->{'maxboxes'} >> 1;
    $self->{'belt'} = $belt;
    my $halted : shared = 0;
    $self->{'halted'} = \$halted;

# Return with a specially blessed object

    bless $self,$class.'::Throttled';
} #new

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2..N parameters to be passed as a box onto the belt

sub put {

# Obtain the object
# Return now if nothing to do

    my $belt = shift;
    return unless @_;

# Make sure we're the only one putting things on the belt
# Freeze the parameters and put it in a box on the belt
# Signal the other worker threads that there is a new box on the belt

    lock( @$belt );
    push( @$belt,$belt->_freeze( \@_ ) );
    cond_signal( @$belt );
} #put

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N parameters returned from a box on the belt

sub take {

# Obtain the object
# Create an empty box

    my $belt = shift;
    my $box;

# Make sure we're the only one working on the belt
# Wait until someone else puts something on the belt
# Take the box off the belt
# Wake up other worker threads if there are stil boxes now

    {lock( @$belt );
     cond_wait( @$belt ) until @$belt;
     $box = shift( @$belt );
     cond_signal( @$belt ) if @$belt;
    } #@$belt

# Thaw the contents of the box and return the result

    @{$belt->_thaw( $box ) };
} #take

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N parameters returned from a box on the belt

sub take_dontwait {

# Obtain the object
# Make sure we're the only one handling the belt
# Return the result of taking of a box if there is one, or an empty list

    my $belt = shift;
    lock( @$belt );
    return @$belt ? $belt->take : ();
} #take_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N references to data-structures in boxes

sub clean {

# Obtain the belt
# Return now after cleaning if we're not interested in the result
# Clean the belt and turn the boxes into references

    my $belt = shift;
    return $belt->_clean unless wantarray;
    map {$belt->_thaw( $_ )} $belt->_clean;
} #clean

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N references to data-structures in boxes

sub clean_dontwait {

# Obtain the belt
# Make sure we're the only one handling the belt
# Return the result of cleaning the belt if there are boxes, or an empty list

    my $belt = shift;
    lock( @$belt );
    return @$belt ? $belt->clean : ();
} #clean_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N parameters returned from a box on the belt

sub peek {

# Obtain the object
# Create an empty box

    my $belt = shift;
    my $box;

# Make sure we're the only one working on the belt
# Wait until someone else puts something on the belt
# Copy the box off the belt
# Wake up other worker threads again

    {lock( @$belt );
     cond_wait( @$belt ) until @$belt;
     $box = $belt->[0];
     cond_signal( @$belt );
    } #@$belt

# Thaw the contents of the box and return the result

    @{$belt->_thaw( $box )};
} #peek

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N parameters returned from a box on the belt

sub peek_dontwait {

# Obtain the object
# Make sure we're the only one handling the belt
# Return the result of taking of a box if there is one, or an empty list

    my $belt = shift;
    lock( @$belt );
    return @$belt ? $belt->peek : ();
} #peek_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 number of boxes still on the belt

sub onbelt { scalar(@{$_[0]}) } #onbelt

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)

sub maxjobs {
    die "Cannot change throttling on a belt that was created unthrottled";
} #maxjobs

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)

sub minjobs {
    die "Cannot change throttling on a belt that was created unthrottled";
} #minjobs

#---------------------------------------------------------------------------

# Internal subroutines

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N all frozen boxes on the belt

sub _clean {

# Obtain the belt
# Initialize the list of frozen boxes

    my $belt = shift;
    my @frozen;

# Make sure we're the only one accessing the belt
# Wait until there is something on the belt
# Obtain the entire contents of the belt of we want it
# Clean the belt
# Notify the world again

    {lock( @$belt );
     cond_wait( @$belt ) until @$belt;
     @frozen = @$belt if wantarray;
     @$belt = ();
     cond_broadcast( @$belt );
    } #@$belt

# Return the frozen goods

    @frozen;
} #_clean

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)
#      2 reference to data structure to freeze
# OUT: 1 frozen scalar

sub _freeze { Storable::freeze( $_[1] ) } #_freeze

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)
#      2 frozen scalar to defrost
# OUT: 1 reference to thawed data structure

sub _thaw { Storable::thaw( $_[1] ) } #_thaw

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Conveyor - transport of any data-structure between threads

=head1 SYNOPSIS

    use Thread::Conveyor;
    my $belt = Thread::Conveyor->new( {maxboxes => 50, minboxes => 25} );
    $belt->put( "foo", ["bar"], {"zoo"} );
    my ($foo,$bar,$zoo) = $belt->take;
    my ($foo,$bar,$zoo) = $belt->take_dontwait;
    my ($foo,$bar,$zoo) = $belt->peek;
    my ($foo,$bar,$zoo) = $belt->peek_dontwait;
    my $onbelt = $belt->onbelt;

    my @box = $belt->clean;
    my @box = $belt->clean_dontwait;
    my ($foo,$bar,$zoo) = @{$box[0]};

    $belt->maxboxes( 100 );
    $belt->minboxes( 50 );

=head1 DESCRIPTION

                  *** A note of CAUTION ***

 This module only functions on Perl versions 5.8.0 and later.
 And then only when threads are enabled with -Dusethreads.  It
 is of no use with any version of Perl before 5.8.0 or without
 threads enabled.

                  *************************

The Thread::Conveyor object is a thread-safe data structure that mimics the
behaviour of a conveyor belt.  One or more worker threads can put boxes with
frozen values and references on one end of the belt to be taken off by one
or more worker threads on the other end of the belt to be thawed and returned.

A box may consist of any combination of scalars and references to scalars,
arrays (lists) and hashes.  Freezing and thawing is currently done with the
L<Storable> method, but that may change in the future.  Objects and code
references are currently B<not> allowed.

By default, the maximum number of boxes on the belt is limited to B<50>.
Putting of boxes on the belt is halted if the maximum number of boxes is
exceeded.  This throttling feature was added because it was found that
excessive memory usage could be caused by having the belt growing too large.
Throttling can be disabled if so desired.

=head1 CLASS METHODS

=head2 new

 $belt = Thread::Conveyor->new(
  {
   maxboxes => 50,
   minboxes => 25,
  }
 );

The "new" function creates a new empty belt.  It returns the instantiated
Thread::Conveyor object.

The input parameter is a reference to a hash.  The following fields are
B<optional> in the hash reference:

=over 2

=item maxboxes

 maxboxes => 50,

 maxboxes => undef,  # disable throttling

The "maxboxes" field specifies the B<maximum> number of boxes that can be
sitting on the belt to be handled (throttling).  If a new L<put> would
exceed this amount, putting of boxes will be halted until the number of
boxes waiting to be handled has become at least as low as the amount
specified with the "minboxes" field.

Fifty boxes will be assumed for the "maxboxes" field if it is not specified.
If you do not want to have any throttling, you can specify the value "undef"
for the field.  But beware!  If you do not have throttling active, you may
wind up using excessive amounts of memory used for storing all of the boxes
that have not been handled yet.

The L<maxboxes> method can be called to change the throttling settings
during the lifetime of the object.

=item minboxes

 minboxes => 25, # default: maxboxes / 2

The "minboxes" field specified the B<minimum> number of boxes that can be
waiting on the belt to be handled before the L<put>ting of boxes is allowed
again (throttling).

If throttling is active and the "minboxes" field is not specified, then
half of the "maxboxes" value will be assumed.

The L<minboxes> method can be called to change the throttling settings
during the lifetime of the object.

=back

=head1 OBJECT METHODS

The following methods operate on the instantiated Thread::Conveyor object.

=head2 put

 $belt->put( 'string',$scalar,[],{} );

The "put" method freezes all the specified parameters together in a box and
puts the box on the beginning of the belt.

=head2 take

 ($string,$scalar,$listref,$hashref) = $belt->take;

The "take" method waits for a box to become available at the end of the
belt, removes that box from the belt, thaws the contents of the box and
returns the resulting values and references.

=head2 take_dontwait

 ($string,$scalar,$listref,$hashref) = $belt->take_dontwait;

The "take_dontwait" method, like the L<take> method, removes a box from the
end of the belt if there is a box waiting at the end of the belt.  If there
is B<no> box available, then the "take_dontwait" method will return
immediately with an empty list.  Otherwise the contents of the box will be
thawed and the resulting values and references will be returned.

=head2 clean

 @box = $belt->clean;
 ($string,$scalar,$listref,$hashref) = @{$box[0]};

The "clean" method waits for one or more boxes to become available at the
end of the belt, removes B<all> boxes from the belt, thaws the contents of
the boxes and returns the resulting values and references as an array
where each element is a reference to the original contents of each box.

=head2 clean_dontwait

 @box = $belt->clean_dontwait;
 ($string,$scalar,$listref,$hashref) = @{$box[0]};

The "clean_dontwait" method, like the L<clean> method, removes all boxes
from the end of the belt if there are any boxes waiting at the end of the
belt.  If there are B<no> boxes available, then the "clean_dontwait" method
will return immediately with an empty list.  Otherwise the contents of the
boxes will be thawed and the resulting values and references will be
returned an an array where each element is a reference to the original
contents of each box.

=head2 peek

 ($string,$scalar,$listref,$hashref) = $belt->peek;

The "peek" method waits for a box to become availabe at the end of the
belt, but does B<not> remove it from the belt like the L<take> method does.
It does however thaw the contents and returns the resulting values and
references.

=head2 peek_dontwait

 ($string,$scalar,$listref,$hashref) = $belt->peek_dontwait;

The "peek_dontwait" method is like the L<take_dontwait> method, but does
B<not> remove the box from the belt if there is one available.  If there
is a box available, then the contents of the box will be thawed and the
resulting values and references are returned.  An empty list will be
returned if there was no box available at the end of the belt.

=head2 onbelt

 $onbelt = $belt->onbelt;

The "onbelt" method returns the number of boxes that are still in the belt.

=head2 maxboxes

 $belt->maxboxes( 100 );
 $maxboxes = $belt->maxboxes;

The "maxboxes" method returns the maximum number of boxes that can be on the
belt before throttling sets in.  The input value, if specified, specifies the
new maximum number of boxes that may be on the belt.  Throttling will be
switched off if the value B<undef> is specified.

Specifying the "maxboxes" field when creating the object with L<new> is
equivalent to calling this method.

The L<minboxes> method can be called to specify the minimum number of boxes
that must be on the belt before the putting of boxes is allowed again after
reaching the maximum number of boxes.  By default, half of the "maxboxes"
value is assumed.

=head2 minboxes

 $belt->minboxes( 50 );
 $minboxes = $belt->minboxes;

The "minboxes" method returns the minimum number of boxes that must be on the
belt before the putting of boxes is allowed again after reaching the maximum
number of boxes.  The input value, if specified, specifies the new minimum
number of boxes that must be on the belt.

Specifying the "minboxes" field when creating the object with L<new> is
equivalent to calling this method.

The L<maxboxes> method can be called to set the maximum number of boxes that
may be on the belt before the putting of boxes will be halted.

=head1 CAVEATS

Passing unshared values between threads is accomplished by serializing the
specified values using C<Storable> when putting a box of values on the belt
and removing the values from a box.  This allows for great flexibility at
the expense of more CPU usage.  It also limits what can be passed, as e.g.
code references and blessed objects can B<not> be serialized and therefore
not be passed.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 HISTORY

This module started life as "Thread::Queue::Any" and as a sub-class of
L<Thread::Queue>.  Using the conveyor belt metaphore seemed more appropriate
and therefore the name was changed.  To cut the cord with Thread::Queue
completely, the belt mechanism was implemented from scratch.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<threads>, L<threads::shared>, L<Thread::Queue>, L<Storable>.

=cut
