# provide backward compatibility for Config::Grammar
package Smokeping::Config;
use strict;
use warnings;

our @ISA;

BEGIN {
    require Config::Grammar;
    if($Config::Grammar::VERSION ge '1.10') {
        require Config::Grammar::Dynamic;
        @ISA = qw(Config::Grammar::Dynamic);
    }
    else {
        @ISA = qw(Config::Grammar);
    }
}

1;
