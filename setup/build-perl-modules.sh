#!/bin/bash

dir=`dirname $0`;
. $dir/sdbs.inc


for module in `perl -ne 'chomp; print qq{$_ }' $dir/../PERL_MODULES `; do
    perlmodule $module
done
    
        
