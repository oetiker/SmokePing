#!/bin/bash

. `dirname $0`/sdbs.inc

for module in \
    FCGI \
    CGI \
    CGI::Fast \
    Config::Grammar \
    Digest::HMAC_MD5 \
    Net::Telnet \
    Net::OpenSSH \
    Net::SNMP \
    Net::LDAP \
    Net::DNS \
    IO::Pty \
    LWP \
; do
    perlmodule $module
done

        
