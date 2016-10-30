# NAME

Data::Math - arithmetic operations on complex data structures

# SYNOPSIS

    use Data::Math;
    my $db = Data::Math->new();

    # add values in two parallel structures
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

# DESCRIPTION

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
operations on (e.g. 'tax\_rate') you can define a pattern
in the object's skip\_key\_patterns array to skip it.

## METHODS

- new

    Creates a new Data::Math object.

    Takes a hash as an argument (i.e. a list of key/value pairs),
    to provide named fields that become object attributes.
    These attributes are:

    - string\_policy

        If the values aren't numbers, instead of the numeric
        operation, they'll be handled according to the string\_policy.
        The default is concat\_if\_differ.  If there are two different
        strings, they will be joined together using the [join\_char](https://metacpan.org/pod/join_char)
        (if not, the string is just passed through).

        Other allowed settings for string\_policy:

            "pick_one"   if there are two different values, use the first one.
            "pick_2nd"   if there are two different values, use the second.

    - join\_char

        Defaults to "|".

    - skip\_key\_patterns

        Skip numeric operation on keys that match any of this list of patterns.

    - skip\_policy

        Default: "pick\_one", meaning that when we skip applying the
        numeric operation, by default we'll just pass through the
        value unchanged, picking the first if they differ.

        The set of allowed skip policies is a superset of the string\_policies.
        In addition to a string\_policy, there's also the 'remove\_key'
        policy, which will remove the matching keys from the result set.

- calc

    Takes an arithmetic operator given as a quoted string as the
    first argument and applies it to the following references to data
    structures.

    Allowed operators: '+', '-', '\*', '/' and '%'

- do\_calc

    do\_calc does recursive descent of two roughly parallel perl
    structures, performing the indicated operation on each,
    storing the result in a newly created parallel structure
    (a reference passed in as the third argument).

    Typically, the indicated operation is a simple numeric operator,
    defaulting to '+'.  The operator may be supplied as the 'op' option:

        $self->do_calc( $structure1, $structure2, $result_structure, { op => '-' };

- qualify\_hash

    Given two hash references, returns a joint list of keys,
    and two "qualified" versions of the hashes, where undef
    values are replaced with default values based on the type
    of what's in the parallel location in the other hash.

    Example usage:

        my ($keys, $qh1, $qh2) = $self->qualify_hash( $ds1, $ds2 );

- qualify\_array

    Given two array references, returns the maximum index limit
    and two "qualified" versions of the arrays, where undef
    values are replaced with default values based on the type
    of what's in the parallel location in the other hash.

    Example usage:

        my ( $limit, $aref1, $aref2 ) = $self->qualify_array( $aref1, $aref2 );

- numeric\_handler

    Perform the indicated numeric operation on the two arguments.
    The operation is passed in as an option named "op", included in
    the options hashref in the third position.

    Example usage:

        my $result =
          $self->numeric_handler( $ds1, $ds2, { op => '-' } );

- string\_handler

    Handle two string arguments, according to the "string\_policy"
    defined for this object.  The default string handling behavior is
    to pass through the existing string if there's just one available
    or if there are two, to concatenate them using the object's
    "join\_char" (typically a '|').

    Other allowed values of "string\_policy" are:

        "pick_one"   if there are two different values, use the first one.
        "pick_2nd"   if there are two different values, use the second.

    Example usage:

        my $result = $self->string_handler( $ds1, $ds2 );

        # override object level string_policy
        my $result = $self->string_handler( $ds1, $ds2, 'pick_one' );

# TODO

    o  look into 'preserve_source' options and such to
       improve memory efficiency

    o  try an operator overload interface

    o  examine possibility of arbitrary user-defineable
       operations (pattern/action callbacks?)

# AUTHOR

Joseph Brenner, <doom@kzsu.stanford.edu>

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Joseph Brenner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.
