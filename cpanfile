requires 'FCGI';
requires 'CGI';
requires 'CGI::Fast';
requires 'Config::Grammar';
requires 'Socket6';
requires 'IO::Socket::SSL';
requires 'Digest::HMAC_MD5';
requires 'Net::Telnet';
requires 'Net::OpenSSH';
requires 'Net::SNMP';
requires 'Net::LDAP';
requires 'Net::DNS';
requires 'IO::Pty';
requires 'LWP';
requires 'Authen::Radius';
requires 'Path::Tiny';
requires 'MIME::Base64';
requires 'InfluxDB::HTTP';
requires 'InfluxDB::LineProtocol';
# JSON::MaybeXS and Object::Result are required by InfluxDB::HTTP but were not
# listed in that lib's dependencies, so we need to cover for them here.
# See: https://github.com/raphaelthomas/InfluxDB-HTTP/issues/10
requires 'JSON::MaybeXS';
requires 'Object::Result';
