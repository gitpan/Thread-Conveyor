package Thread::Conveyor::Thread;

# Make sure we are a belt
# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our @ISA : unique = qw(Thread::Conveyor);
our $VERSION : unique = '0.06';
use strict;

# Number of times this namespace has been CLONEd

my $cloned = 0;

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# Class methods

#---------------------------------------------------------------------------
#  IN: 1 class with which to bless the object
#      2 reference to parameter hash
# OUT: 1 instantiated object

sub new {

# Obtain the class
# Make sure we have a blessed object so we can do stuff with it
# Save the clone level (so we can check later if we've been cloned)

    my $class = shift;
    my $self = bless shift,$class;
    $self->{'cloned'} = $cloned;

# Create the shared belt semaphore
# Create the accessing thread semaphore
# Create the shared belt data channel
# Create the shared maxboxes value
# Create the shared minboxes value
# Store references to these inside the object

    my $belt : shared;
    my $command : shared;
    my $data : shared;
    my $maxboxes : shared = $self->{'maxboxes'};
    my $minboxes : shared = $self->{'minboxes'};
    @$self{qw(belt command data maxboxes minboxes)} =
     (\$belt,\$command,\$data,\$maxboxes,\$minboxes);

# Start the thread, save the thread object on the fly
# Wait for the thread to take control
# Return with the instantiated object

    $self->{'thread'} = threads->new( \&_handler,$self );
    threads->yield until defined($command);
    $self;
} #new

#---------------------------------------------------------------------------

# Object methods

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2..N parameters to be passed as a box onto the belt

sub put {

# Obtain the object
# Return now if nothing to do

    my $self = shift;
    return unless @_;

# Prepare the data to be put
# While we're not yet successful
#  Handle the put command, return if successful
#  Give up this timeslice

    my $frozen = Thread::Serialize::freeze( @_ );
    while (1) {
        return if $self->_handle( 1,$frozen );
        threads->yield;
    }
} #put

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 internal flag: command number to use (default: 2 = take)
#      3 internal value: index into belt when peeking
# OUT: 1..N parameters returned from a box on the belt

sub take {

# Obtain the object
# Set the command number

    my $self = shift;
    my $todo = shift || 2;
    my $index = shift;

# While we're not yet successful
#  Perform the required command and get the result
#  Return now with the requested data if successful
#  Give up this timeslice

    while (1) {
        my ($ok,$data) = $self->_handle( $todo,$index );
        return Thread::Serialize::thaw( $data ) if $ok;
	threads->yield;
    }
} #take

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 internal flag: command number to use (default: 2 = take)
#      3 internal value: index into belt when peeking
# OUT: 1..N parameters returned from a box on the belt

sub take_dontwait {

# Obtain the object
# Handle the required command and obtain the result
# Return with whatever was returned

    my $self = shift;
    my ($ok,$data) = $self->_handle( (shift || 2),shift );
    return $ok ? Thread::Serialize::thaw( $data ) : ();
} #take_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 ordinal number of value to peek (default: 0)
# OUT: 1..N parameters returned from a box on the belt

sub peek { shift->take( 3,shift || 0 ) } #peek

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 ordinal number of value to peek (default: 0)
# OUT: 1..N parameters returned from a box on the belt

sub peek_dontwait { shift->take_dontwait( 3,shift || 0 ) } #peek_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 internal flag: dont wait
# OUT: 1..N references to data-structures in boxes

sub clean {

# Obtain the object and the dontwait flag
# Set the actual command to be used
# While we're not yet successful
#  Handle the clean command and obtain the result

    my ($self,$dontwait) = @_;
    my $todo = defined( wantarray ) ? 4 : 5;
    while (1) {
        my ($ok,$data) = $self->_handle( $todo );

#  If the action was successful
#   Return now without anything if in void context
#   Return with references to the thawed data
#  Elseif we don't want to wait
#   Return now with empty list
#  Give up this timeslice

        if ($ok) {
             return unless defined(wantarray);
             return map {[Thread::Serialize::thaw( $_ )]}
	      Thread::Serialize::thaw( $data );
        } elsif( $dontwait ) {
             return ();
        }
	threads->yield;
    }
} #clean

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1..N references to data-structures in boxes

sub clean_dontwait { shift->clean( 1 ) } #clean_dontwait

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 number of boxes still on the belt

sub onbelt {

# Obtain the object
# Return now indicating nothing on the belt if shut down
# Have the onbelt command executed and return the result

    my $self = shift;
    return 0 if $self->{'shutdown'};
    ($self->_handle( 6 ))[1];
} #onbelt

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)

sub maxboxes {

# Obtain the object
# Die if it wasn't throttled to begin with

    my $self = shift;
    die "Cannot change throttling on a belt that was created unthrottled"
     unless $self->{'maxboxes'};

# If there is a new value
#  Set it
#  Set the appropriate minoboxes value also
# Return the (new) value

    if (@_) {
        ${$self->{'maxboxes'}} = shift;
        ${$self->{'minboxes'}} = ${$self->{'maxboxes'}} >> 1;
    }
    ${$self->{'maxboxes'}};
} #maxboxes

#---------------------------------------------------------------------------
#  IN: 1 instantiated object (ignored)

sub minboxes {

# Obtain the object
# Die if it wasn't throttled to begin with

    my $self = shift;
    die "Cannot change throttling on a belt that was created unthrottled"
     unless $self->{'maxboxes'};

# Set it if there is a new value
# Return the (new) value

    ${$self->{'minboxes'}} = shift if @_;
    ${$self->{'minboxes'}};
} #minboxes

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 flag: dont wait for belt to be emptied

sub shutdown {

# Obtain the parameters
# Return now if we're already shutdown
# Mark the object as shutdown

    my ($self,$dontwait) = @_;
    return if exists $self->{'shutdown'};
    $self->{'shutdown'} = 1;

# If we're supposed to wait
#  Give the chance to other threads while there is stuff on the belt

    unless ($dontwait) {
        threads->yield while $self->onbelt;
    }

# Execute the shutdown command
# Wait for the thread to actually finish

    $self->_handle( 0 );
    $self->{'thread'}->join;
} #shutdown

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread object

sub thread { shift->{'thread'} } #thread

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 tid of thread of belt

sub tid { shift->{'thread'}->tid } #tid

#---------------------------------------------------------------------------

# Internal subroutines for outside the conveyor thread

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 belt semaphore

sub _belt { shift->{'belt'} } #_belt

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 command to execute
#      3 data to be sent (optional)
# OUT: 1 flag: whether action performed
#      2 result of action (optional)

sub _handle {

# Obtain the object
# Obtain the references to the belt, command and data fields

    my $self = shift;
    my ($belt,$command,$data) = @$self{qw(belt command data)};

# Initialize the counter
# While we haven't got access to the handler
#  Give up this timeslice if we tried this before
#  Wait for access to the belt
#  Reloop if we got access here before the handler was waiting again

    my $tries;
    AGAIN: while (1) {
        threads->yield if $tries++;
        {lock( $belt );
         next AGAIN if defined( $$belt );

# Indicate we're in charge now and command and data
# Signal the handler to do its thing

         ($$belt,$$command,$$data) = (threads->tid+1,@_);
         threads::shared::cond_signal( $belt );
        } #$belt

#  Wait for the handler to be done with this request
#  Obtain local copy of result
#  Indicate that the caller is ready with the request
#  Return result of the action

        threads->yield until $$belt < 0;
        ($command,$data) = ($$command,$$data);
        undef( $$belt );
        return wantarray ? ($command,$data) : $command;
    }
} #_handle

#---------------------------------------------------------------------------

# Internal subroutines for inside the conveyor thread

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub _handler {

# Obtain a reference to the wait routine (so that we can zap the namespace)
# Obtain a reference to the yield routine (so that we can zap the namespace)
# Create a reference to the freeze routine (so that we can zap the namespace)
    
    my $wait = \&threads::shared::cond_wait;
    my $yield = \&threads::yield;
    my $freeze = \&Thread::Serialize::freeze;

# Allow for non-strict references
# For all of the modules that are loaded
#  Reloop if an absolute path
#  Remove knowledge of it being loaded
#  Turn it into a module name

    {no strict 'refs';
     foreach (keys %INC) {
         next if m#^/#; # absolute path in %INC?
         delete( $INC{$_} );
         s#\.pm$##; s#/#::#g;

#  Zap the stash of the module
#  Recreate with just an undefined version (otherwise segfaults occur)

         eval {
	  undef( %{$_.'::'} );
          undef( ${$_.'::VERSION'} );
	 }
     }
    }

# Obtain the object
# Obtain the references to the fields that we need

    my $self = shift;
    my ($belt,$command,$data,$maxboxes,$minboxes) =
     @$self{qw(belt command data maxboxes minboxes)};

# Create the actual belt
# Create the actual halted flag
# Take control of the belt
# Indicate to the world we've taken control

    my @belt;
    my $halted;
    lock( $belt );
    $$command = 0;

# While we're accepting things to do
#  Wait for something to do
#  Outloop when we're done
#  Start the dispatcher array

    while (1) {
        $wait->( $belt );
        last unless $$command;
        (0,					# 0 = exit thread

#  If we're throttling
#   If we're halted now (no action)
#   Elseif we're throttling and we're above the limit now
#    Set halted flag
#   Else (we may push)
#    Push the data on the belt
#   Indicate failure or success
#  Else (we're not throttling)
#   Push the data on the belt and indicate success

         sub {					# 1 = put
          if ($$maxboxes) {
              if ($halted) {
              } elsif ($$maxboxes and @belt >= $$maxboxes) {
                  $halted = 1;
              } else {
                  push( @belt,$$data );
              }
	      $$command = !$halted;
          } else {
              $$command = push( @belt,$$data );
          }
         },

#  Set the result flag
#  Fetch a value from the belt if there is one

         sub {					# 2 = take
          $$command = @belt;
          $$data = shift( @belt );
         },

#  Set the result flag
#  Copy a value from the belt if there is one

         sub {					# 3 = peek
          $$command = @belt;
          $$data = $belt[$$data];
         },

#  Set the result flag
#  Copy the frozen belt if there is someting to get
#  Reset the belt

         sub {					# 4 = clean and save
          $$command = @belt;
          $$data = $freeze->( @belt );
          @belt = ();
         },

#  Indicate success or failure
#  Reset the belt

         sub {					# 5 = clean
          $$command = @belt;
          @belt = ();
         },

#  Set number of entries on belt
#  Indicate success

         sub {					# 6 = onbelt
          $$data = @belt;
          $$command = 1;
         },

#  Execute the appropriate handler
#  Reset halted flag if halted initially and now below threshold
#  Indicate that we're done
#  Wait for the result to be picked up

        )[$$command]->();
        $halted = (@belt <= $$minboxes) if $halted;
        $$belt = -$$belt;
        &$yield while defined( $$belt );
    }

# Indicate that we're done

    $$belt = -$$belt;
} #_handler

#---------------------------------------------------------------------------

# Routines for standard Perl features

#---------------------------------------------------------------------------
#  IN: 1 namespace being cloned (ignored)

sub CLONE { $cloned++ } #CLONE

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub DESTROY {

# Return now if we're in a rogue DESTROY

    return unless UNIVERSAL::isa( $_[0],__PACKAGE__ ); #HACK

# Obtain the object
# Return now if we're not allowed to run DESTROY

    my $self = shift;
    return unless $self->{'cloned'} == $cloned;

# Tell the thread to quit now

    $self->shutdown( 1 );
} #DESTROY

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Conveyor::Thread - thread implementation of Thread::Conveyor

=head1 DESCRIPTION

This class should not be called by itself, but only with a call to
L<Thread::Conveyor>.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Thread::Conveyor>.

=cut
