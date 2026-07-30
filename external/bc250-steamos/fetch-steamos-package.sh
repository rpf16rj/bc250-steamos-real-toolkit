#!/bin/bash
# Fetch an exact SteamOS package from whichever stable Jupiter channel carries it.
# Exit 3 means every successfully contacted channel definitively lacked it;
# other retrieval failures exit 1 so callers do not mistake an outage for 404.
set -euo pipefail

[ "$#" = 2 ] || { echo "Usage: $0 <package.pkg.tar.zst> <destination>" >&2; exit 2; }

PACKAGE=$1
DEST=$2
MIRROR=${MIRROR:-https://steamdeck-packages.steamos.cloud/archlinux-mirror}

case "$PACKAGE" in
    */*|'') echo "Invalid package filename: $PACKAGE" >&2; exit 2 ;;
    *.pkg.tar.zst) ;;
    *) echo "Unsupported package filename: $PACKAGE" >&2; exit 2 ;;
esac

valid_archive() {
    [ -s "$1" ] && tar --zstd -tf "$1" >/dev/null 2>&1
}

if valid_archive "$DEST"; then
    echo "Already downloaded: $PACKAGE"
    exit 0
fi

mkdir -p "$(dirname "$DEST")"
TMP=$(mktemp "${DEST}.part.XXXXXX")
trap 'rm -f "$TMP"' EXIT

if [ -n "${HDR_REPOS:-}" ]; then
    REPOS=$HDR_REPOS
else
    # Versioned release channels often carry packages that are absent from
    # jupiter-main. Ignore staging/CI channels, which are not shipped releases.
    INDEX=$(curl --retry 2 --connect-timeout 10 -fsSL "$MIRROR/") \
        || { echo "Could not read the SteamOS package index: $MIRROR/" >&2; exit 1; }
    DISCOVERED=$(printf '%s' "$INDEX" \
        | grep -oE 'href="jupiter-[^"/]+/"' \
        | sed 's|^href="||; s|/"$||' \
        | grep -vxE 'jupiter-(main|ci-test|staging.*)' \
        | sort -rV | tr '\n' ' ') || DISCOVERED=
    REPOS="jupiter-main $DISCOVERED"
fi

PROBED=
UNCERTAIN=
for repo in $REPOS; do
    case "$repo" in
        jupiter-[A-Za-z0-9._-]*) ;;
        *) echo "Ignoring invalid SteamOS repository name: $repo" >&2; UNCERTAIN="$UNCERTAIN invalid-repository"; continue ;;
    esac
    case " $PROBED " in *" $repo "*) continue ;; esac
    PROBED="$PROBED $repo"
    URL="$MIRROR/$repo/os/x86_64/$PACKAGE"
    if ! HTTP=$(curl --retry 2 --connect-timeout 10 --max-time 20 \
        -sSIL -o /dev/null -w '%{http_code}' "$URL"); then
        UNCERTAIN="$UNCERTAIN $repo(network)"
        continue
    fi
    case "$HTTP" in
        2*) ;;
        404|410) continue ;;
        *) UNCERTAIN="$UNCERTAIN $repo(HTTP-$HTTP)"; continue ;;
    esac

    echo "Fetching $PACKAGE from $repo ..."
    if curl --retry 3 --retry-all-errors -fL -o "$TMP" "$URL" \
        && valid_archive "$TMP"; then
        mv -f "$TMP" "$DEST"
        trap - EXIT
        echo "Downloaded: $DEST"
        exit 0
    fi
    echo "Package download from $repo was incomplete or invalid; trying another channel." >&2
    UNCERTAIN="$UNCERTAIN $repo(download)"
    : > "$TMP"
done

if [ -n "$UNCERTAIN" ]; then
    echo "Could not reliably retrieve $PACKAGE from a stable Jupiter channel." >&2
    echo "Uncertain:$UNCERTAIN" >&2
    STATUS=1
else
    echo "Could not find $PACKAGE on a stable Jupiter channel." >&2
    STATUS=3
fi
echo "Probed:${PROBED:- none}" >&2
echo "Set HDR_REPOS='jupiter-...' or MIRROR=... to override discovery." >&2
exit "$STATUS"
