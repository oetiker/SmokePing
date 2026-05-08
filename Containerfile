FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV SMOKEPING_PREFIX=/opt/smokeping

# System dependencies: build tools + runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    make gcc autoconf automake perl curl ca-certificates \
    # Runtime: rrdtool + perl bindings
    rrdtool librrds-perl \
    # Probes
    fping dnsutils \
    # Web server
    lighttpd \
    # Perl modules available as system packages
    libcgi-pm-perl libfcgi-perl libcgi-fast-perl \
    libwww-perl libnet-dns-perl libnet-snmp-perl \
    libio-socket-ssl-perl libsocket6-perl \
    libdigest-hmac-perl libnet-telnet-perl \
    libnet-ldap-perl libauthen-radius-perl \
    libpath-tiny-perl libmime-base64-perl \
    libjson-maybexs-perl \
    # For cpanm to build XS modules
    libc6-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install cpanm
RUN curl -sL https://cpanmin.us | perl - App::cpanminus

# Copy source
COPY . /build/smokeping
WORKDIR /build/smokeping

# Install remaining Perl deps not available as system packages
# Note: InfluxDB::HTTP, InfluxDB::LineProtocol, Object::Result are optional
# (only needed for InfluxDB integration) and skipped here.
RUN cpanm --notest --quiet \
    Net::OpenSSH \
    IO::Pty \
    Config::Grammar \
    FCGI

# Build and install SmokePing
# Skip thirdparty (deps handled via apt/cpanm) and doc (no man pages needed)
RUN ./configure --prefix=${SMOKEPING_PREFIX} --enable-pkgonly \
    && for dir in lib bin etc htdocs; do make -C $dir install; done

# Create required directories
RUN mkdir -p \
    ${SMOKEPING_PREFIX}/data \
    ${SMOKEPING_PREFIX}/cache \
    ${SMOKEPING_PREFIX}/var

# Install container-specific config files
COPY container/smokeping-config ${SMOKEPING_PREFIX}/etc/config
COPY container/lighttpd.conf /etc/lighttpd/lighttpd.conf
COPY container/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Clean up build directory
RUN rm -rf /build

EXPOSE 4265

ENTRYPOINT ["/entrypoint.sh"]
