package CGI::Session::Serialize::default;

# $Id: default.pm 351 2006-11-24 14:16:50Z markstos $ 

use strict;
use Safe;
use Data::Dumper;
use CGI::Session::ErrorHandler;
use Scalar::Util qw(blessed reftype refaddr);
use Carp "croak";
use vars qw( %overloaded );
require overload;

@CGI::Session::Serialize::default::ISA = ( "CGI::Session::ErrorHandler" );
$CGI::Session::Serialize::default::VERSION = '4.20';


sub freeze {
    my ($class, $data) = @_;
    
    my $d =
    new Data::Dumper([$data], ["D"]);
    $d->Indent( 0 );
    $d->Purity( 1 );
    $d->Useqq( 0 );
    $d->Deepcopy( 0 );
    $d->Quotekeys( 1 );
    $d->Terse( 0 );
    
    # ;$D added to make certain we get our data structure back when we thaw
    return $d->Dump() . ';$D';
}

sub thaw {
    my ($class, $string) = @_;

    # To make -T happy
     my ($safe_string) = $string =~ m/^(.*)$/s;
     my $rv = Safe->new->reval( $safe_string );
    if ( $@ ) {
        return $class->set_error("thaw(): couldn't thaw. $@");
    }
    __walk($rv);
    return $rv;
}

sub __walk {
    my %seen;
    my @filter = __scan(shift);
    local %overloaded;
    
    while (defined(my $x = shift @filter)) {
        $seen{refaddr $x || ''}++ and next;
          
        my $r = reftype $x or next;
        if ($r eq "HASH") {
            # we use this form to make certain we have aliases
            # to the values in %$x and not copies
            push @filter, __scan(@{$x}{keys %$x});
        } elsif ($r eq "ARRAY") {
            push @filter, __scan(@$x);
        } elsif ($r eq "SCALAR" || $r eq "REF") {
            push @filter, __scan($$x);
        }
    }
}

# we need to do this because the values we get back from the safe compartment 
# will have packages defined from the safe compartment's *main instead of
# the one we use
sub __scan {
    # $_ gets aliased to each value from @_ which are aliases of the values in 
    #  the current data structure
    for (@_) {
        if (blessed $_) {
            if (overload::Overloaded($_)) {
                my $address = refaddr $_;

                # if we already rebuilt and reblessed this item, use the cached
                # copy so our ds is consistent with the one we serialized
                if (exists $overloaded{$address}) {
                    $_ = $overloaded{$address};
                } else {
                    my $reftype = reftype $_;                
                    if ($reftype eq "HASH") {
                        $_ = $overloaded{$address} = bless { %$_ }, ref $_;
                    } elsif ($reftype eq "ARRAY") {
                        $_ = $overloaded{$address} =  bless [ @$_ ], ref $_;
                    } elsif ($reftype eq "SCALAR" || $reftype eq "REF") {
                        $_ = $overloaded{$address} =  bless \do{my $o = $$_},ref $_;
                    } else {
                        croak "Do not know how to reconstitute blessed object of base type $reftype";
                    }
                }
            } else {
                bless $_, ref $_;
            }
        }
    }
    return @_;
}


1;

__END__;

=pod

=head1 NAME

CGI::Session::Serialize::default - Default CGI::Session serializer

=head1 DESCRIPTION

This library is used by CGI::Session driver to serialize session data before storing it in disk.

All the methods are called as class methods.

=head1 METHODS

=over 4

=item freeze($class, \%hash)

Receives two arguments. First is the class name, the second is the data to be serialized. Should return serialized string on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=item thaw($class, $string)

Received two arguments. First is the class name, second is the I<frozen> data string. Should return thawed data structure on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=back

=head1 LICENSING

For support and licensing see L<CGI::Session|CGI::Session>

=cut

