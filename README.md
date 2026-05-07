```
 ____                  _        ____  _
/ ___| _ __ ___   ___ | | _____|  _ \(_)_ __   __ _
\___ \| '_ ` _ \ / _ \| |/ / _ \ |_) | | '_ \ / _` |
 ___) | | | | | | (_) |   <  __/  __/| | | | | (_| |
|____/|_| |_| |_|\___/|_|\_\___|_|   |_|_| |_|\__, |
                                              |___/
```

[![Build Test](https://github.com/oetiker/SmokePing/actions/workflows/build-test.yaml/badge.svg)](https://github.com/oetiker/SmokePing/actions/workflows/build-test.yaml)

SmokePing is a latency measurement and graphing tool. It runs a daemon
that sends test packets at regular intervals and records the results in
RRD files. A CGI frontend renders the data as interactive graphs with
loss indication, trend analysis and alerting.

## Features

- **Multi-protocol probing** — ICMP (FPing), TCP SYN, DNS, HTTP/HTTPS (Curl), SSH, LDAP, Radius, and [40+ more probes](#probes)
- **Loss visualization** — packet loss is shown as color-coded marks on the latency graph, making intermittent problems visible at a glance
- **Alerting** — configurable pattern-based alerts via email or custom scripts, supporting matchers like threshold, loss, median deviation
- **Master/Slave** — distribute measurements across multiple locations, aggregate results in one place
- **Hierarchies** — organize targets into multiple views (by location, owner, function) from a single configuration
- **Charts** — automatically generated "top-N" pages using pluggable sorters (highest loss, highest median, most variance)
- **Multi-host graphs** — overlay measurements from different targets into a single comparison graph
- **Dynamic IP support** — targets can update their IP address via a web call
- **Extensible** — write your own probes, matchers and sorters as Perl modules
- **RRDtool backend** — compact storage, automatic consolidation, fast rendering

## Quick Start

### Prerequisites

- Perl 5.10.1+
- RRDtool with Perl bindings (`librrds-perl` on Debian/Ubuntu, `perl-rrdtool` on RedHat)
- FPing (for ICMP probing — the default probe)
- A webserver with CGI/FastCGI support, or use the included Mojolicious development server

**Debian/Ubuntu:**

```bash
sudo apt install rrdtool librrds-perl fping libssl-dev
```

**RedHat/CentOS:**

```bash
sudo yum install rrdtool perl-rrdtool fping openssl-devel
```

### Build & Install

```bash
./configure --prefix=/opt/smokeping
```

If `configure` reports missing Perl modules, run the suggested build
command and re-run `configure`. Then:

```bash
make install
```

### Configure

Copy and edit the example configuration:

```bash
cd /opt/smokeping
cp etc/config.dist etc/config
vi etc/config
```

The config file is documented in `smokeping_config(5)`. The included
`config.dist` has examples for FPing, DNS, Curl and TCPPing probes,
multi-host comparison graphs, hierarchies and alerts.

### Run

Start in debug mode first to verify everything works:

```bash
/opt/smokeping/bin/smokeping --config=/opt/smokeping/etc/config --debug
```

Then start as a daemon:

```bash
/opt/smokeping/bin/smokeping --config=/opt/smokeping/etc/config --logfile=/var/log/smokeping.log
```

### Web Interface

For production, configure your webserver to serve the CGI. With Apache and `mod_fcgid`:

```apache
ScriptAlias /smokeping/smokeping.cgi /opt/smokeping/htdocs/smokeping.fcgi
Alias /smokeping /opt/smokeping/htdocs
<Directory /opt/smokeping/htdocs>
    Options FollowSymLinks
</Directory>
```

For development and testing, a built-in Mojolicious server is included:

```bash
cd /opt/smokeping
perl serve.pl
# open http://localhost:8888
```

## Probes

| Probe | Protocol | Tool |
|-------|----------|------|
| FPing / FPing6 | ICMP | [fping](https://www.fping.org/) |
| FPingContinuous | ICMP (continuous) | fping |
| Curl / AnotherCurl | HTTP/HTTPS | [curl](https://curl.se/) |
| DNS / AnotherDNS | DNS | [dig](https://www.isc.org/bind/) |
| TCPPing | TCP SYN | [tcpping](https://github.com/deajan/tcpping) |
| SSH / AnotherSSH | SSH | [OpenSSH](https://www.openssh.org/) |
| EchoPing* | TCP/UDP/ICMP/HTTP/DNS/LDAP/SMTP | [echoping](https://github.com/bortzmeyer/echoping/) |
| TraceroutePing | Traceroute | traceroute |
| IRTT | IRTT | [irtt](https://github.com/heistp/irtt) |
| LDAP | LDAP | Net::LDAP |
| Radius | RADIUS | Authen::Radius |
| CiscoRTTMon* | IP SLA | SNMP |
| DismanPing | DISMAN-PING | SNMP |
| NFSping | NFS | [nfsping](https://github.com/mprovost/NFSping) |
| Qstat | Game servers | [qstat](https://github.com/multiplay/qstat) |
| SipSak | SIP | [sipsak](https://github.com/nils-ohlmeier/sipsak) |
| TacacsPlus | TACACS+ | Authen::TacacsPlus |
| SendEmail | SMTP | Net::SMTP |

See `smokeping -man Smokeping::probes::<Name>` for per-probe documentation.

## Documentation

| Topic | Command |
|-------|---------|
| Configuration reference | `man smokeping_config` |
| Installation guide | `man smokeping_install` |
| Writing custom probes | `man smokeping_extend` |
| Master/Slave setup | `man smokeping_master_slave` |
| Upgrading | `man smokeping_upgrade` |
| CLI tools | `man smokeping`, `man smokeinfo`, `man tSmoke` |

Online: <https://oss.oetiker.ch/smokeping/doc/index.en.html>

## Project Structure

```
bin/            CLI tools (smokeping, smokeinfo, tSmoke)
etc/            Configuration templates (config.dist, basepage.html)
htdocs/         Web assets (CSS, JavaScript)
lib/Smokeping/  Core Perl modules
  probes/       Measurement probe plugins
  sorters/      Chart sorting plugins
  matchers/     Alert matcher plugins
doc/            Man pages and examples
```

## License

GNU General Public License v2 or later. See [LICENSE](LICENSE).

## Authors

Tobias Oetiker and Niko Tyni

See [CONTRIBUTORS](CONTRIBUTORS) for the full list.
