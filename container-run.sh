#!/bin/bash
set -e

IMAGE_NAME="smokeping"
CONTAINER_NAME="smokeping"

usage() {
    echo "Usage: $0 [build|run|stop|clean]"
    echo ""
    echo "  build   Build the container image (auto-cleans old images)"
    echo "  run     Run the container (build first if needed)"
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
    podman build -t "${IMAGE_NAME}" .
    prune_old_images
}

do_run() {
    local port="${SMOKEPING_PORT:-4265}"

    # Stop old container if running
    if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
        echo "Stopping existing ${CONTAINER_NAME}..."
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    fi

    # Build if image doesn't exist
    if ! podman image exists "${IMAGE_NAME}"; then
        do_build
    fi

    local run_args=(
        --name "${CONTAINER_NAME}"
        -p "${port}:4265"
        --cap-add=NET_RAW
        --rm
    )

    # Optional: persistent data volume
    if [ -n "${SMOKEPING_DATA}" ]; then
        mkdir -p "${SMOKEPING_DATA}"
        run_args+=(-v "${SMOKEPING_DATA}:/opt/smokeping/data")
    fi

    echo "Starting ${CONTAINER_NAME} on port ${port}..."
    echo "Web UI: http://localhost:${port}/smokeping.cgi"
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
    stop)  do_stop ;;
    clean) do_clean ;;
    *)     usage; exit 1 ;;
esac
