package Thread::Conveyor;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.01';
use strict;

# Make sure we have threads
# Make sure we can share and wait and signal
# Make sure we have Storable

use threads; ();
use threads::shared qw(cond_wait cond_signal);
use Storable ();

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# Class methods

#---------------------------------------------------------------------------
#  IN: 1 class with which to bless the object
# OUT: 1 instantiated object

sub new {

# Create the conveyor belt
# Bless it as the object

    my @belt : shared;
    bless \@belt,shift;
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
    push( @$belt,Storable::freeze( \@_ ) );
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

    @{Storable::thaw( $box ) };
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

    @{Storable::thaw( $box )};
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

__END__

=head1 NAME

Thread::Conveyor - transport of any data-structure

=head1 SYNOPSIS

    use Thread::Conveyor;
    my $belt = Thread::Conveyor->new;
    $belt->put( "foo", ["bar"], {"zoo"} );
    my ($foo,$bar,$zoo) = $belt->take;
    my ($foo,$bar,$zoo) = $belt->take_dontwait;
    my ($foo,$bar,$zoo) = $belt->peek;
    my ($foo,$bar,$zoo) = $belt->peek_dontwait;
    my $onbelt = $belt->onbelt;

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

=head1 CLASS METHODS

=head2 new

 $belt = Thread::Conveyor->new;

The "new" function creates a new empty belt.  It returns the instantiated
Thread::Conveyor object.

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

L<threads>, L<threads::shared>, <Thread::Queue>, L<Storable>.

=cut
