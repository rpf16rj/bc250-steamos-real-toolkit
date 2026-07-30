#!/bin/bash
# Prepare an exact Kbuild tree for the running SteamOS kernel. The default path
# requires exact symbols. --wifi may omit Module.symvers when the running
# kernel has module versioning disabled; the AIC8800 build checks this again.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WIFI=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --wifi) WIFI=1 ;;
        *)      ARGS+=("$arg") ;;
    esac
done
[ "${#ARGS[@]}" -le 1 ] || { echo "usage: $0 [--wifi] [kernel-tree]" >&2; exit 1; }
TREE=${ARGS[0]:-$HERE/valve-kernel}

[ "$(id -u)" != 0 ] || { echo "FATAL: prepare the kernel as the normal user, not root" >&2; exit 1; }
"$HERE/ensure-build-prereqs.sh"
command -v flock >/dev/null || { echo "FATAL: flock is required" >&2; exit 1; }

exec 9>"$HERE/.prepare-kernel.lock"
flock 9

"$HERE/fetch-sources.sh" "$TREE"
BUILD_ARGS=(--prepare-only)
[ "$WIFI" = 0 ] || BUILD_ARGS+=(--allow-missing-symvers)
"$HERE/build.sh" "${BUILD_ARGS[@]}" "$TREE"
