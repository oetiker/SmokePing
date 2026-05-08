#!/bin/bash
set -e

SMOKEPING_PREFIX=/opt/smokeping

# Ensure data directories exist
mkdir -p "${SMOKEPING_PREFIX}/data" "${SMOKEPING_PREFIX}/cache" "${SMOKEPING_PREFIX}/var"

echo "Starting SmokePing daemon..."
"${SMOKEPING_PREFIX}/bin/smokeping" \
    --config="${SMOKEPING_PREFIX}/etc/config" \
    --nodaemon \
    --logfile=stdout &

SMOKEPING_PID=$!

echo "Starting lighttpd on port 4265..."
lighttpd -D -f /etc/lighttpd/lighttpd.conf &
LIGHTTPD_PID=$!

# Shut down cleanly on SIGTERM/SIGINT
trap "kill $SMOKEPING_PID $LIGHTTPD_PID 2>/dev/null; wait; exit 0" SIGTERM SIGINT

echo "SmokePing is running. Web UI: http://localhost:4265/"

# Wait for either process to exit
wait -n
exit $?
