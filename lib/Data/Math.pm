package Data::Math;
use Moo;
use MooX::Types::MooseLike::Base qw(:all);

=head1 NAME

Data::Math - arithmetic operations on complex data structures

=head1 SYNOPSIS

   use Data::Math;
   my $db = Data::Math->new();
   # adding structures
   my $data_sum = $dm->calc( '+', $data_structure_1, $data_structure_2 );


   # subtracting data structures
   %gross = ( de => 2345.37,
              es => 1238.99,
              us => 1.98,
             );
   %costs = ( de => 35.00,
              es => 259.11,
              us => 666.66,
             );
   my $net = $dm->calc( '-', \%gross, \%costs );

   #    $net:
   #         { 'de' => '2310.37',
   #           'es' => '979.88',
   #           'us' => '-664.68' };

=head1 DESCRIPTION

Data::Math is for doing arithmetic operations on roughly
parallel data structures.

It's pretty clear what a line like this would be meant to do,
though Perl does nothing useful with it:

   %net = %gross - %costs;

Instead, Data::Math's calc method can be used:

   my $net = $dm->calc( '-', \%gross, \%costs );

The code here is customizeable in many ways, but has
defaults that should make it easy to use in simple
cases.  The arithmetic operator is applied to numbers,
strings are just passed through if both sides are the same,
or concatenated (with '|' separator) if they differ.

If there's a numeric field you don't want to do numeric
operations on (e.g. 'vat_tax') you can define a pattern
in the object's skip_key_patterns array to skip it.

=head2 METHODS

=over

=item new

Creates a new Data::Math object.

Takes a hash as an argument (i.e. a list of key/value pairs),
to provide named fields that become object attributes.
These attributes are:

=over

=item string_policy

If the values aren't numbers, instead of the numeric
operation, they'll be handled according to the string_policy.
The default is concat_if_differ.  If there are two different
strings, they will be joined together using the L<join_char>
(if not, the string is just passed through).

Other allowed settings for string_policy:

   "pick_one"   if there are two different values, use the first one.
   "pick_2nd"   if there are two different values, use the second.

=item join_char

Defaults to "|".

=item skip_key_patterns

Skip numeric operation on keys that match any of this list of patterns.

=item skip_policy

Default: "pick_one", meaning that when we skip applying the
numeric operation, by default we'll just pass through the
value unchanged, picking the first if they differ.

The set of allowed skip policies is a superset of the string_policies.
In addition to a string_policy, there's also the 'remove_key'
policy, which will remove the matching keys from the result set.

=back

=cut

use 5.008;
use Carp;
use Data::Dumper;

use List::MoreUtils qw( uniq any );
use Scalar::Util qw( reftype looks_like_number );
use List::Util qw( max );

use lib "/home/doom/End/Cave/DataMath/Wall/Data-Math/lib"; # DEBUG

use Scalar::Classify qw( classify classify_pair );

# ### TODO actually, probably drop this "actions" idea.
# has actions =>
#     (is => 'rw',  isa => ArrayRef, default => sub{ [] }, lazy => 1);

has string_policy =>
    (is => 'rw',  isa => Str, default => 'concat_if_differ' );

has join_char =>
    (is => 'rw',  isa => Str, default => '|' );

# array of qr{}s
has skip_key_patterns =>
    (is => 'rw',  isa => ArrayRef );

has skip_policy =>
    (is => 'rw',  isa => Str, default => 'pick_one' );

# # EXPERIMENTAL
# # on by default, can set to 0 to reduce memory use
# has preserve_source =>
#     (is => 'rw',  isa => Int, default => 1 );


our $VERSION = '0.01';
my $DEBUG = 0;  # TODO change to 0 before shipping

=item calc

Simple wrapper method around do_calc, expects an
arithmetic operator given as a quoted string as the
first argument:

Allowed operators: '+', '-', '*', '/' and '%'

=cut


# Experimental version intended to handle multivalued case
sub calc {
  my $self = shift;
  my $op   = shift;

  my ($ds1, $ds2, $new);
  $ds1 = shift;
  while( @_ ) {
    $ds2 = shift;

    # just a hack?   for perl: undef + undef = 0
    if ( not ( defined( $ds1 ) ) && not ( defined( $ds2 ) ) ) {
      $ds1 = 0;
      $ds2 = 0;
    }

    $new = classify_pair( $ds1, $ds2, { mismatch_policy => 'error' } );

    my $ref = \( $new );
    $self->do_calc( $ds1, $ds2, $ref, { op => $op } );

    $ds1 = $new;
  }

  return $new;
}



=item do_calc

do_calc does recursive descent of two roughly parallel perl
structures, performing the indicated operation on each,
storing the result in a newly created parallel structure.

Typically, the indicated operation is a simple numeric operator,
defaulting to '+'.  The operator may be supplied as the 'op' option:

  my $result_structure =
    $self->do_calc( $structure1, $structure2, { op => '-' };

=cut

sub do_calc {
  my $self = shift;
  my $ds1  = shift;
  my $ds2  = shift;
  my $ref  = shift;

  my $opt     = shift;
  my $op = $opt->{op} || '+';

  my $skip_key_patterns = $self->skip_key_patterns;
  my $skip_policy       = $self->skip_policy;

  my ( $new, $refcode, $class ) =
    classify_pair( $ds1, $ds2, { mismatch_policy => 'error' } );

  return unless defined $refcode;

  # First, we do the scalar cases
  if ( $refcode eq ':NUMBER:' ) {
    my $result =
      $self->numeric_handler( $ds1, $ds2, { op => $op } );
    ${ $ref } = $result;
  }
  elsif ( $refcode eq ':STRING:' ) {
    my $result =
      $self->string_handler( $ds1, $ds2 );
    ${ $ref } = $result;
  } else { # working on refs

    # ultimately, we call do_calc recursively but we need to first
    # put the right default in the new structure we're building up.

    # Need to expand the ref and call do_calc on each item,
    # first creating a parallel location, and passing a *ref* to the
    # parallel location as new_ref.

    ${ $ref } = $new;

    if ($refcode eq 'HASH') {
# TODO MEMSAVE (maybe)
#      my ($qh1, $qh2) = $self->qualify_hash_memsave( $ds1, $ds2 );
      my ($keys, $qh1, $qh2) = $self->qualify_hash( $ds1, $ds2 );

    KEY:
# TODO MEMSAVE
#      foreach my $k ( keys %{ $qh1 } ) {
      foreach my $k ( @{ $keys } ) {
        my $v1 = $qh1->{ $k };
        my $v2 = $qh2->{ $k };

        # skip key feature
        foreach my $rule ( @{ $skip_key_patterns } ) {
          if( $k =~ /$rule/ ) {

            unless( $skip_policy eq 'remove_key' ) { # TODO implement other policies

              # default behavior is just use first value
              # ${ $ref }->{ $k } = $v1;

             # almost same thing (passes all existing tests)
              ${ $ref }->{ $k } =
                $self->string_handler( $v1, $v2, $skip_policy );

             # TODO support all string_policy as skip_policy,
             #      by using string_handler like this with a policy override
             #      Also support a skip policy of "treat_as_string"
             #      using object-level string_policy

            }
            next KEY;
          }
        }

        my $new = classify_pair( $v1, $v2, { mismatch_policy => 'error' } );

        # Need to assign *this* $new to the given point
        # to the href in the output structure, using this key
        # Then get a reference to this and use in recursive call to do_calc.
        # (Gotta be a better way to express this.)
        ${ $ref }->{ $k } = $new;
        my $item_ref = \( ${ $ref }->{ $k } );

        $self->do_calc(  $v1, $v2, $item_ref, $opt );
      } # next foreach my $k
    }
    elsif ($refcode eq 'ARRAY') {
      my ($limit, $vals1, $vals2) = $self->qualify_array( $ds1, $ds2 );

      foreach my $i ( 0 .. $limit ) {
        my $v1 = $vals1->[ $i ];
        my $v2 = $vals2->[ $i ];
        my $item_ref = \( $new->[ $i ] );
        $self->do_calc(  $v1, $v2, $item_ref, $opt );
      }
    }
  }
}



=item qualify_array

Given two array references, returns the maximum index limit
and two "qualified" versions of the arrays, where undef
values are replaced with default values based on the type
of what's in the parallel location in the other hash.

Note: qualify_array *modifies* the original arrays in place
(despite the fact that we also return references to them).

Example usage:

   my ( $limit, $aref1, $aref2 ) = $self->qualify_array( $aref1, $aref2 );

=cut

# TODO
#      "preserve_source" option to leave initial arrays
#      untouched by default, but can be flipped off to allow
#      munging them to preserve memory

#   my ($limit, $vals1, $vals2) = $self->qualify_array( $aref1, $aref2 );

sub qualify_array {
  my $self = shift;
  my $a1   = shift || [];
  my $a2   = shift || [];

  my $policy_opt = { mismatch_policy => 'error'};

  # my $preserve_source = $self->preserve_source; # EXPERIMENTAL

  my $lim1 = $#{ $a1 };
  my $lim2 = $#{ $a2 };

  my $limit = max( $lim1, $lim2 );

   # Make copies (burning memory to avoid touching originals)
   my @new1 = @{ $a1 };
   my @new2 = @{ $a2 };

  # replace undefs on one side with default depending on other side:
  #    e.g.  0  ''  []  {}
  foreach my $i (  0 .. $limit ) {
    classify_pair( $new1[ $i ], $new2[ $i ], { also_qualify => 1 } );
  }
  return ( $limit, \@new1, \@new2 );
}


=item qualify_hash

Given two hash references, returns a joint list of keys,
and two "qualified" versions of the hashes, where undef
values are replaced with default values based on the type
of what's in the parallel location in the other hash.

Example usage:

  my ($keys, $qh1, $qh2) = $self->qualify_hash( $ds1, $ds2 );

=cut

sub qualify_hash {
  my $self = shift;
  my $h1   = shift;
  my $h2   = shift;

  no warnings 'uninitialized';  # TODO

  my @keys = uniq ( keys %{ $h1 }, keys %{ $h2 } );

  my ( %new1, %new2 );
  foreach my $key ( @keys ) {
    $new1{ $key } = $h1->{ $key };
    $new2{ $key } = $h2->{ $key };

    classify_pair( $new1{ $key }, $new2{ $key }, { also_qualify => 1 } );
  }

  return (\@keys, \%new1, \%new2 );
}


=item qualify_hash_memsave

Given two hash references, returns two "qualified" versions of
the hashes where undef values are replaced with default values
based on the type of what's in the parallel location in the other
hash.

Example usage:

  my ($qh1, $qh2) = $self->qualify_hash_memsave( $ds1, $ds2 );

Unlike qualify_hash, this does not create a unified list of keys.
That can be obtained from *either* hash though:

  my @keys =  keys %{ $qh1 };

=cut

# TODO wouldn't a *real* memsave version do a qualify-in-place?
sub qualify_hash_memsave {
  my $self = shift;
  my $h1   = shift;
  my $h2   = shift;

  no warnings 'uninitialized';  ### TODO

  my ( %new1, %new2 );
  foreach my $key ( keys %{ $h1 } ) {

    $new1{ $key } = $h1->{ $key };
    $new2{ $key } = $h2->{ $key };

    classify_pair( $new1{ $key }, $new2{ $key }, { also_qualify => 0 } );
  }

 KEY:
  foreach my $key ( keys %{ $h2 } ) {
    # skip this key if we've done it already
    next KEY if exists $h2->{ $key };

    $new1{ $key } = $h1->{ $key };
    $new2{ $key } = $h2->{ $key };

    classify_pair( $new1{ $key }, $new2{ $key }, { also_qualify => 0 } );
  }

  return ( \%new1, \%new2 );
}



=item numeric_handler

Perform the indicated numeric operation on the two arguments.
The operation is passed in as an option named "op", included in
the options hashref in the third position.

Example usage:

    my $result =
      $self->numeric_handler( $ds1, $ds2, { op => '-' } );

=cut

sub numeric_handler {
  my $self = shift;
  my $s1     = shift;
  my $s2     = shift;
  my $opt    = shift;

  my $op = $opt->{op} || '+';
  my $result;
  $s1 = 0 if( $s2 && not( $s1 ) );
  $s2 = 0 if( $s1 && not( $s2 ) );

  if ( $op eq '+' ) {
    $result = $s1 + $s2;
  } elsif ( $op eq '-' ) {
    $result = $s1 - $s2;
  } elsif ( $op eq '*' ) {
    $result = $s1 * $s2;
  } elsif ( $op eq '/' ) {
    $result = $s1 / $s2
  } elsif ( $op eq '%' ) {
    $result = $s1 % $s2
  }
  return $result;
}



=item string_handler

Handle two string arguments, according to the "string_policy"
defined for this object.  The default string handling behavior is
to pass through the existing string if there's just one available
or if there are two, to concatenate them using the object's
"join_char" (typically a '|').

Other allowed values of "string_policy" are:

   "pick_one"   if there are two different values, use the first one.
   "pick_2nd"   if there are two different values, use the second.


Example usage:

    my $result = $self->string_handler( $ds1, $ds2 );

    # override object level string_policy
    my $result = $self->string_handler( $ds1, $ds2, 'pick_one' );


=cut

sub string_handler {
  my $self = shift;
  my $s1      = shift;
  my $s2      = shift;
  my $policy  = shift || $self->string_policy;
  my $join_char   = $self->join_char;

  # silence complaints when doing 'ne' on an undef
  no warnings 'uninitialized';

  my $result;

  if ($policy eq 'default' || $policy eq 'concat_if_differ') {
    # print STDERR "MEEP: concat_if_differ\n";
    if ( $s1 ne $s2 ) {
      if ( not( defined $s1 ) || $s1 eq '' ) {
        $result =  $s2;
      } elsif ( not( defined $s2 ) || $s2 eq '' ) {
        $result =  $s1;
      } else {
        $result = $s1 . $join_char. $s2;
      }
    } elsif ( $s1 eq $s2 ) {
      $result = $s1;
    }
  }
  elsif ( $policy eq 'pick_one') {

    if ( $s1 ne $s2 ) {
      if (  not( defined $s2 ) || $s2 eq '' ) {
        $result =  $s1;
      } elsif ( not( defined $s1 ) || $s1 eq '' ) {
        $result =  $s2;
      } else {
        $result = $s1; # favor the first if the second is different
      }
    } elsif ( $s1 eq $s2 ) {
      $result = $s1;
    }
  }

  elsif ( $policy eq 'pick_2nd') {
    if ( $s1 ne $s2 ) {
      if ( not( defined $s1 ) || $s1 eq '' ) {
        $result =  $s2;
      } elsif ( not( defined $s2 ) || $s2 eq '' ) {
        $result =  $s1;
      } else {
        $result = $s2; # favor the second if it differs from the first
      }
    } elsif ( $s1 eq $s2 ) {
      $result = $s2;
    }
  } else {
    carp "Data::Math: Unsupported string_policy: $policy";
  }
  return $result;
}

1;

# A Mouse/Moose performance tweak
__PACKAGE__->meta->make_immutable();

1;

=back

=head1 TODO

  o  re-examine pattern/action callbacks

  o  operator overloaded interface

=head1 HISTORY

I wrote a very simple module to do something like this at work:
It was a recursive implementation that only covered features I
needed immediately for what I was doing then.

My second attempt at it used a totally different queue
architecture, and it's since been renamed Data::Math::Queue
(it may someday be completed and released, or it may not).
It was an attempt at optimization that I concluded was definitely
premature-- it's too hard to work on the design in that form.
I may come back to it some day, particularly if the recursive
version seems to have performance limitations.

Actually, the usual efficiency argument against recursion
probably doesn't apply in this case,  because actual perl data
structures are likely to be more wide than deep.  Depth first
recursion will bottom out quickly, and is unlikely to overwork
the stack.

After giving up on the queue implementation (for now), I returned
to a recursive approach.  I no longer remember what the first version
of this code looked like, so this might as well be a "clean room"
rewrite.

There are a number of features I worked on and then abandoned
(for now):

  o  in addition to handling the standard numeric operations,
     I was thinking about adding a "pattern/action" language so
     that in principle you could use this as a general
     recursion engine to do anything.  It seems unlikely to me
     that this feature would be very popular, so it's on hold.

  o  ...

=head1 AUTHOR

Joseph Brenner, E<lt>jbrenner@ffn.comE<gt>,
11 Sep 2014


=cut
