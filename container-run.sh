#!/bin/bash
set -e

IMAGE_NAME="smokeping"
CONTAINER_NAME="smokeping"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $0 [build|run|dev|stop|clean]"
    echo ""
    echo "  build   Build the container image (auto-cleans old images)"
    echo "  run     Run the container (build first if needed)"
    echo "  dev     Run with live-mounted htdocs, config, and lighttpd.conf"
    echo "          (edit files locally, reload browser to see changes)"
    echo "  stop    Stop the running container"
    echo "  clean   Stop and remove container + all images"
    echo ""
    echo "Environment variables:"
    echo "  SMOKEPING_PORT  Host port to map (default: 4265)"
    echo "  SMOKEPING_DATA  Host path for RRD data persistence (optional)"
}

prune_old_images() {
    local dangling
    dangling=$(podman images --filter "dangling=true" -q 2>/dev/null)
    if [ -n "$dangling" ]; then
        echo "Removing dangling images..."
        podman image prune -f >/dev/null
    fi
}

do_build() {
    echo "Building ${IMAGE_NAME} container..."
    podman build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
    prune_old_images
}

stop_existing() {
    if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
        echo "Stopping existing ${CONTAINER_NAME}..."
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    fi
}

do_run() {
    local port="${SMOKEPING_PORT:-4265}"
    stop_existing

    if ! podman image exists "${IMAGE_NAME}"; then
        do_build
    fi

    local run_args=(
        --name "${CONTAINER_NAME}"
        -p "0.0.0.0:${port}:4265"
        --cap-add=NET_RAW
        --rm
    )

    if [ -n "${SMOKEPING_DATA}" ]; then
        mkdir -p "${SMOKEPING_DATA}"
        run_args+=(-v "${SMOKEPING_DATA}:/opt/smokeping/data")
    fi

    echo "Starting ${CONTAINER_NAME} on port ${port}..."
    echo "Web UI: http://localhost:${port}/"
    podman run "${run_args[@]}" "${IMAGE_NAME}"
}

do_dev() {
    local port="${SMOKEPING_PORT:-4265}"
    stop_existing

    if ! podman image exists "${IMAGE_NAME}"; then
        do_build
    fi

    local run_args=(
        --name "${CONTAINER_NAME}"
        -p "0.0.0.0:${port}:4265"
        --cap-add=NET_RAW
        --rm
        # Live-mount: edit locally, reload browser
        -v "${SCRIPT_DIR}/htdocs/css:/opt/smokeping/htdocs/css:ro"
        -v "${SCRIPT_DIR}/htdocs/js:/opt/smokeping/htdocs/js:ro"
        -v "${SCRIPT_DIR}/htdocs/img:/opt/smokeping/htdocs/img:ro"
        -v "${SCRIPT_DIR}/etc/basepage.html.dist:/opt/smokeping/etc/basepage.html.dist:ro"
        -v "${SCRIPT_DIR}/container/smokeping-config:/opt/smokeping/etc/config:ro"
        -v "${SCRIPT_DIR}/container/lighttpd.conf:/etc/lighttpd/lighttpd.conf:ro"
    )

    if [ -n "${SMOKEPING_DATA}" ]; then
        mkdir -p "${SMOKEPING_DATA}"
        run_args+=(-v "${SMOKEPING_DATA}:/opt/smokeping/data")
    fi

    echo "Starting ${CONTAINER_NAME} in DEV mode on port ${port}..."
    echo "Web UI: http://localhost:${port}/"
    echo ""
    echo "Live-mounted (edit + reload browser):"
    echo "  htdocs/css/          -> /opt/smokeping/htdocs/css/"
    echo "  htdocs/js/           -> /opt/smokeping/htdocs/js/"
    echo "  htdocs/img/          -> /opt/smokeping/htdocs/img/"
    echo "  etc/basepage.html.dist -> /opt/smokeping/etc/basepage.html.dist"
    echo "  container/smokeping-config -> /opt/smokeping/etc/config"
    echo "  container/lighttpd.conf    -> /etc/lighttpd/lighttpd.conf"
    echo ""
    echo "Note: lighttpd.conf changes require container restart (stop + dev)"
    echo "      SmokePing config changes require container restart"
    echo "      CSS/JS/HTML changes are instant (just reload browser)"
    podman run "${run_args[@]}" "${IMAGE_NAME}"
}

do_stop() {
    echo "Stopping ${CONTAINER_NAME}..."
    podman stop "${CONTAINER_NAME}" 2>/dev/null || true
}

do_clean() {
    do_stop
    echo "Removing image ${IMAGE_NAME} and dangling images..."
    podman rmi "${IMAGE_NAME}" 2>/dev/null || true
    podman image prune -f >/dev/null 2>&1 || true
}

case "${1:-run}" in
    build) do_build ;;
    run)   do_run ;;
    dev)   do_dev ;;
    stop)  do_stop ;;
    clean) do_clean ;;
    *)     usage; exit 1 ;;
esac
