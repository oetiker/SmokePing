requires 'perl', '5.024000';

# Core dependencies - main daemon, CGI, and master/slave operation
requires 'Config::Grammar';
requires 'Digest::HMAC_MD5';
requires 'LWP::UserAgent';
requires 'RRDs';
requires 'URI::Escape';

# Probe: AnotherDNS
recommends 'Net::DNS';
recommends 'IO::Socket::INET6';

# Probe: LDAP
recommends 'Net::LDAP';
recommends 'IO::Socket::SSL';

# Probe: Radius
recommends 'Authen::Radius';

# Probe: TacacsPlus
recommends 'Authen::TacacsPlus';

# Probe: OpenSSHEOSPing, OpenSSHJunOSPing
recommends 'Net::OpenSSH';

# Probe: TelnetIOSPing, TelnetJunOSPing
recommends 'Net::Telnet';

# Probe: IRTT
recommends 'JSON::PP';
recommends 'Path::Tiny';

# Built-in web server (run.sh)
recommends 'Mojolicious';

# CGI FastCGI mode
recommends 'CGI::Fast';
recommends 'FCGI';

# InfluxDB export support
recommends 'InfluxDB::HTTP';
recommends 'InfluxDB::LineProtocol';
# These are required by InfluxDB::HTTP but missing from its own dependencies.
# See: https://github.com/raphaelthomas/InfluxDB-HTTP/issues/10
recommends 'JSON::MaybeXS';
recommends 'Object::Result';
