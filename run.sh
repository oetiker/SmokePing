#!/bin/bash
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
SP="$BASEDIR/smokeping"
PORT="${1:-5847}"

# Auto-detect rrdtool PERL5LIB
for d in "$BASEDIR"/rrdtool/lib/perl/*/; do
    [ -d "$d" ] && export PERL5LIB="${d}:${PERL5LIB:-}"
done

# Add SmokePing lib and local perl modules
export PERL5LIB="$SP/lib:$HOME/perl5/lib/perl5:$PERL5LIB"

# Create required directories
mkdir -p "$SP"/{cache,data,var}

# Create config from dist if needed
if [ ! -f "$SP/etc/config" ]; then
    cp "$SP/etc/config.dist" "$SP/etc/config"
    perl -i -pe "s|^(cgiurl\s*=\s*).*|\$1http://localhost:$PORT/|" "$SP/etc/config"
    echo "Created $SP/etc/config (cgiurl → http://localhost:$PORT/)"
else
    echo "Using existing $SP/etc/config"
fi

# Check config
"$SP/bin/smokeping" --config="$SP/etc/config" --check 2>&1 || {
    echo "Config check failed!"
    exit 1
}
echo "Config OK"

# Kill any existing daemon
if [ -f "$SP/var/smokeping.pid" ]; then
    kill "$(cat "$SP/var/smokeping.pid")" 2>/dev/null || true
    sleep 1
fi

# Start SmokePing daemon
"$SP/bin/smokeping" \
    --config="$SP/etc/config" \
    --logfile="$SP/var/smokeping.log" \
    --pid-dir="$SP/var"

sleep 1
echo "SmokePing daemon started (PID $(cat "$SP/var/smokeping.pid"))"
echo "Starting web server on http://localhost:$PORT/"

# Export variables for the Mojo app
export SP_BIN="$SP/bin/smokeping_cgi"
export SP_CONFIG="$SP/etc/config"
export SP_HTDOCS="$SP/htdocs"
export SP_CACHE="$SP/cache"
export SP_PORT="$PORT"

# Start Mojolicious web server
exec perl -MMojolicious::Lite -e '
    use strict;
    use warnings;

    my $sp_bin    = $ENV{SP_BIN};
    my $sp_config = $ENV{SP_CONFIG};
    my $sp_htdocs = $ENV{SP_HTDOCS};
    my $sp_cache  = $ENV{SP_CACHE};

    any "/" => sub {
        my $c = shift;

        # Build CGI environment
        local %ENV = %ENV;
        $ENV{REQUEST_METHOD}  = $c->req->method;
        $ENV{QUERY_STRING}    = $c->req->url->query->to_string // "";
        $ENV{SCRIPT_NAME}     = "/";
        $ENV{SERVER_NAME}     = $c->req->url->to_abs->host // "localhost";
        $ENV{SERVER_PORT}     = $c->req->url->to_abs->port // 80;
        $ENV{HTTP_HOST}       = $c->req->headers->host // "localhost";
        $ENV{REMOTE_ADDR}     = $c->tx->remote_address // "127.0.0.1";

        # Capture CGI output
        my $output = qx{$sp_bin $sp_config 2>/dev/null};

        # Split headers and body
        my ($headers, $body) = split /\r?\n\r?\n/, $output, 2;

        my $status = 200;
        my %hdrs;
        for my $line (split /\r?\n/, $headers // "") {
            if ($line =~ /^Status:\s*(\d+)/i) {
                $status = $1;
            } elsif ($line =~ /^([^:]+):\s*(.*)/) {
                $hdrs{$1} = $2;
            }
        }

        $c->res->code($status);
        for my $k (keys %hdrs) {
            $c->res->headers->header($k => $hdrs{$k});
        }
        $c->res->body($body // "");
        $c->rendered;
    };

    # Serve static files
    get "/js/*filepath"    => sub { my $c = shift; $c->reply->file("$sp_htdocs/js/"  . $c->stash("filepath")) };
    get "/css/*filepath"   => sub { my $c = shift; $c->reply->file("$sp_htdocs/css/" . $c->stash("filepath")) };
    get "/cache/*filepath" => sub { my $c = shift; $c->reply->file("$sp_cache/" . $c->stash("filepath")) };

    app->start("daemon", "-l", "http://*:" . ($ENV{SP_PORT} // 5847));
'
