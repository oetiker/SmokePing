FROM debian
MAINTAINER deveshmanish, https://github.com/deveshmanish/SmokePing

# ========================================================================================
# ====== SmokePing
ENV \
    DEBIAN_FRONTEND="noninteractive" \
    HOME="/root" \
    TERM="xterm" \
    PERL_MM_USE_DEFAULT=1 \
    LC_ALL=C \
    LANG=C

# Install base packages and do the build
RUN \
    apt-get update \
&&      apt-get -y upgrade \
&&  apt-get install -y \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cpanminus \
        curl \
        git \
        libnet-ssleay-perl \
        librrds-perl \
        rrdtool \
        unzip \
&&  git clone https://github.com/deveshmanish/SmokePing.git \
&&  cd SmokePing \
&&  ./bootstrap \
&&  ./configure \
&&  make install \
&&  mv htdocs/smokeping.fcgi.dist htdocs/smokeping.fcgi

ENV \
    LIBDIR=/usr/lib/x86_64-linux-gnu \
    PERLDIR=/usr/lib/x86_64-linux-gnu/perl
	
ENV \
    DEBIAN_FRONTEND="noninteractive" \
    HOME="/root" \
    TERM="xterm" \
    APACHE_LOG_DIR="/var/log/apache2" \
    APACHE_LOCK_DIR="/var/lock/apache2" \
    APACHE_PID_FILE="/var/run/apache2.pid" \
    PERL_MM_USE_DEFAULT=1 \
    PERL5LIB=/opt/smokeping/lib \
    LC_ALL=C \
    LANG=C
