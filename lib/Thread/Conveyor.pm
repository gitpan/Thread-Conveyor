package Thread::Conveyor;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.06';
use strict;

# Make sure we have threads
# Make sure we can share;
# Make sure we have serialize

use threads ();
use threads::shared ();
use Thread::Serialize ();

# Set default optimization

my $OPTIMIZE = 'memory';

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

    my $class = shift;
    my $self = shift || {};

# Obtain the optimization to be used
# Set maximum number of boxes if applicable
# Return now with an unthrottled array implementation if so required

    my $optimize = $self->{'optimize'} || $OPTIMIZE;
    $self->{'maxboxes'} = 50 unless exists( $self->{'maxboxes'} );
    return _new( $class.'::Array' )
     if $optimize eq 'cpu' and !$self->{'maxboxes'};

# Set minimum number of boxes if applicable
# Initialize a shared halted flag
# Safe a reference to it in the object

    $self->{'minboxes'} ||= $self->{'maxboxes'} >> 1;
    my $halted : shared = 0;
    $self->{'halted'} = \$halted;

# If we're optmizing for memory
#  Use the ::Thread implementation
# Elseif we're optimizing for CPU
#  Use the ::Throttled implementation
# Die with message

    if ($optimize eq 'memory') {
        return _new( $class.'::Thread',$self );
    } elsif ($optimize eq 'cpu') {
        return _new( $class.'::Throttled',$self );
    }
    die "Don't know how to handle '$optimize' optimization";
} #new

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 new default optimization type
# OUT: 1 current default optimization type

sub optimize {

# Set new optimized value if specified
# Return current optimized value

    $OPTIMIZE = $_[1] if @_ > 1;
    $OPTIMIZE;
} #optimize

#---------------------------------------------------------------------------

# Object methods

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 new maxboxes value (default: no change)
# OUT: 1 current maxboxes value

sub maxboxes {

# Obtain the object
# Set the new maxboxes and minboxes value if new value specified
# Return current value

    my $self = shift;
    $self->{'minboxes'} = ($self->{'maxboxes'} = shift) >> 1 if @_;
    $self->{'maxboxes'};
} #maxboxes

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 new minboxes value (default: no change)
# OUT: 1 current minboxes value

sub minboxes {

# Obtain the object
# Set the new minboxes value if new value specified
# Return current value

    my $self = shift;
    $self->{'minboxes'} = shift if @_;
    $self->{'minboxes'};
} #minboxes

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub shutdown {} #shutdown

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread object associated with belt (always undef)

sub thread { undef } #thread

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread id of thread object associated with belt (always undef)

sub tid { undef } #tid

#---------------------------------------------------------------------------

# Internal subroutines

#---------------------------------------------------------------------------
#  IN: 1 class for which to create object
#      2..N parameters to be passed to it
# OUT: 1 blessed object

sub _new {

# Obtain the class
# Create module name
# Allow non-strict references
# Make sure the sub-module is available
# Return object created with give parameter

    my $class = shift;
    (my $module = $class) =~ s#::#/#g;
    no strict 'refs';
    require $module.'.pm' unless defined( ${$class.'::VERSION'} );
    $class->new( @_ );
} #_new

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Conveyor - transport of any data-structure between threads

=head1 SYNOPSIS

    use Thread::Conveyor;
    my $belt = Thread::Conveyor->new(
     {
      maxboxes => 50,
      minboxes => 25,
      optimize => 'memory', # or 'cpu'
     }
    );

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

    $belt->shutdown;
    $belt->thread;
    $belt->tid;

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
   optimize => 'memory', # or 'cpu'
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

The "minboxes" field specifies the B<minimum> number of boxes that can be
waiting on the belt to be handled before the L<put>ting of boxes is allowed
again (throttling).

If throttling is active and the "minboxes" field is not specified, then
half of the "maxboxes" value will be assumed.

The L<minboxes> method can be called to change the throttling settings
during the lifetime of the object.

=item optimize

 optimize => 'cpu', # default: 'memory'

The "optimize" field specifies which implementation of the belt will be
selected.  Currently there are two choices: 'cpu' and 'memory'.  By default,
the "memory" optimization will be selected if no specific optmization is
specified.

You can call the class method L<optimize> to change the default optimization.

=back

=head2 optimize

 Thread::Conveyor->optimize( 'cpu' );

 $optimize = Thread::Conveyor->optimize;

The "optimize" class method allows you to specify the default optimization
type that will be used if no "optimize" field has been explicitely specified
with a call to L<new>.  It returns the current default type of optimization.

Currently two types of optimization can be selected:

=over 2

=item memory

Attempt to use as little memory as possible.  Currently, this is achieved by
starting a seperate thread which hosts an unshared array.  This uses the
"Thread::Conveyor::Thread" sub-class.

=item cpu

Attempt to use as little CPU as possible.  Currently, this is achieved by
using a shared array (using the "Thread::Conveyor::Array" sub-class),
encapsulated in a hash reference if throttling is activated (then also using
the "Thread::Conveyor::Throttled" sub-class).

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

 @lookahead = $belt->peek( $index );

The "peek" method waits for a box to become availabe at the end of the
belt, but does B<not> remove it from the belt like the L<take> method does.
It does however thaw the contents and returns the resulting values and
references.

For advanced, and mostly internal, usages, it is possible to specify the
ordinal number of the box in which to peek.

=head2 peek_dontwait

 ($string,$scalar,$listref,$hashref) = $belt->peek_dontwait;

 @lookahead = $belt->peek_dontwait( $index );

The "peek_dontwait" method is like the L<take_dontwait> method, but does
B<not> remove the box from the belt if there is one available.  If there
is a box available, then the contents of the box will be thawed and the
resulting values and references are returned.  An empty list will be
returned if there was no box available at the end of the belt.

For advanced, and mostly internal, usages, it is possible to specify the
ordinal number of the box in which to peek.

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

=head2 shutdown

 $belt->shutdown;

The "shutdown" method performs an orderly shutdown of the belt.  It waits
until all of the boxes on the belt have been removed before it returns.

=head2 thread

 $thread = $belt->thread;

The "thread" method returns the thread object that is being used for the belt.
It returns undef if no seperate thread is being used.

=head2 tid

 $tid = $belt->tid;

The "tid" method returns the thread id of the thread object that is being
used for the belt.  It returns undef if no seperate thread is being used.

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
