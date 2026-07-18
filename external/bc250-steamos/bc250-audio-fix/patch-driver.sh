#!/bin/bash
# Single entry point: fetch sources, build, install — the full cycle after a
# SteamOS update. Run as the normal user; sudo is invoked for install only.
#
#   ./patch-driver.sh [--cg|--cg-unvalidated] [kernel-tree]  (default: ./valve-kernel)
#
# --cg / --cg-unvalidated are forwarded to build.sh (EXPERIMENTAL clock-gating
# patches, see build.sh); fetch-sources.sh doesn't know them, so they're
# filtered out there.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" != 0 ] || { echo "run as the normal user — sudo is used for the install step only"; exit 1; }

WITH_CG=()
ARGS=()
for a in "$@"; do
    case "$a" in
        --cg)             WITH_CG=(--cg) ;;
        --cg-unvalidated) WITH_CG=(--cg-unvalidated) ;;
        *)                ARGS+=("$a") ;;
    esac
done

"$HERE/fetch-sources.sh" "${ARGS[@]}"
"$HERE/build.sh" "${WITH_CG[@]}" "${ARGS[@]}"
sudo "$HERE/install.sh"
