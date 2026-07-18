#!/bin/bash
# Fetch everything build.sh needs, for the RUNNING kernel — README runbook
# steps 1-2 as code:
#
#   1. Valve's kernel source at the exact commit in `uname -r`, cloned from
#      the Evlav mirror (github.com/Evlav/linux-integration — the community
#      mirror of Valve's private kernel GitLab; the old gitlab.com/evlaV
#      mirror shuttered 2025-08 and is frozen), plus Module.symvers from the
#      matching linux-neptune-*-headers package on Valve's package mirror
#      (all jupiter-* channels are probed — point releases can ship from a
#      version branch like jupiter-3.8.1x instead of jupiter-main).
#   2. The build deps (pahole, bc, libelf, openssl, zlib) from the SteamOS
#      Arch mirror, extracted into deps/ where build-env.sh expects them.
#
#   ./fetch-sources.sh [kernel-tree]      (default: ./valve-kernel)
#
# Idempotent: already-correct pieces are skipped, so re-run freely after a
# partial failure. Run on the BC-250 (everything keys off `uname -r`; set
# KERNEL_RELEASE=<release> to fetch for another kernel from elsewhere).
# Flow: ./fetch-sources.sh && ./build.sh && sudo ./install.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=${KERNEL_RELEASE:-$(uname -r)}

MIRROR=${MIRROR:-https://steamdeck-packages.steamos.cloud/archlinux-mirror}
KERNEL_REMOTE=${KERNEL_REMOTE:-https://github.com/Evlav/linux-integration.git}
KERNEL_API=${KERNEL_API:-https://api.github.com/repos/Evlav/linux-integration}
DEP_PKGS=(pahole bc libelf openssl zlib glibc linux-api-headers)
# SteamOS 3.9 strips /usr/include from the image, so HOSTCC can't find even
# sys/types.h. The libraries themselves (libc.so, crt*.o) are still installed,
# so for these two packages only usr/include is extracted — pulling glibc's
# usr/lib into deps/ would shadow the system libc via LD_LIBRARY_PATH.
HEADERS_ONLY_PKGS=(glibc linux-api-headers)
DEP_REPOS=(extra-main core-main)

die()  { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

step "derive package names from kernel release"
# e.g. 6.16.12-valve24.2-1-neptune-616-g57ac0765fe0d
#      <kver>--------------|pkgrel|flavor-----|sha
case "$REL" in
    *-neptune-*-g*) ;;
    *) die "'$REL' does not look like a SteamOS neptune kernel release — run on the BC-250 (or set KERNEL_RELEASE)" ;;
esac
SHA=${REL##*-g}
REST=${REL%-g"$SHA"}
FLAVOR=${REST##*-neptune-}
MID=${REST%-neptune-"$FLAVOR"}
PKGREL=${MID##*-}
KVER=${MID%-"$PKGREL"}
PKGVER=${KVER//-/.}   # Arch pkgver can't hold hyphens: 6.16.12-valve24.2 -> 6.16.12.valve24.2
HDRPKG=linux-neptune-$FLAVOR-headers-$PKGVER-$PKGREL-x86_64.pkg.tar.zst
echo "kernel:  $REL"
echo "commit:  $SHA"
echo "headers: $HDRPKG"

step "kernel source tree (runbook step 1)"
TREE=${1:-$HERE/valve-kernel}
PARKED=$TREE-dot-git

at_target() { [[ "$(git --git-dir="$1" rev-parse HEAD 2>/dev/null)" == "$SHA"* ]]; }

if [ -d "$PARKED" ] && at_target "$PARKED"; then
    echo "tree already at $SHA (.git parked) — nothing to do"
elif [ -d "$TREE/.git" ] && at_target "$TREE/.git"; then
    echo "tree already at $SHA — nothing to do"
else
    if [ -d "$PARKED" ]; then
        # parked but at the wrong commit (SteamOS updated) — unpark to fetch;
        # build.sh re-parks
        [ -d "$TREE/.git" ] && die "both $TREE/.git and $PARKED exist — resolve by hand first"
        mv "$PARKED" "$TREE/.git"
        echo "unparked $PARKED -> $TREE/.git"
    fi
    if [ ! -d "$TREE/.git" ]; then
        [ -e "$TREE" ] && [ -n "$(ls -A "$TREE" 2>/dev/null)" ] \
            && die "$TREE exists without .git — cannot verify its commit; move it aside"
        mkdir -p "$TREE"
        git -C "$TREE" init -q
        git -C "$TREE" remote add origin "$KERNEL_REMOTE"
        echo "initialized $TREE (remote: $KERNEL_REMOTE)"
    fi

    # `git fetch` needs the full 40-char sha; uname -r only carries 12.
    # Resolve via the GitHub API (or pass FULLSHA=<40-hex> to skip).
    FULLSHA=${FULLSHA:-$(curl -fsSL "$KERNEL_API/commits/$SHA" \
        | grep -oE '"sha": *"[0-9a-f]{40}"' | grep -oE '[0-9a-f]{40}')} \
        || die "could not resolve $SHA via $KERNEL_API — offline, rate-limited, or the mirror has not synced this release yet (it lags Valve by up to ~a week after a SteamOS update; 6.16.12-valve24.4 took 6 days). Retry later, or pass FULLSHA=<40-hex-sha>. Valve's own signed full source is always up at $MIRROR/sources/<channel>/linux-neptune-$FLAVOR-$PKGVER-$PKGREL.src.tar.gz if you cannot wait (manual: build.sh expects a git tree)"
    FULLSHA=${FULLSHA%%$'\n'*}   # commit's own sha is the first match (no -m1: early grep exit SIGPIPEs curl under pipefail)
    [[ "$FULLSHA" == "$SHA"* ]] || die "API returned $FULLSHA which does not start with $SHA"
    echo "resolved: $FULLSHA"

    if ! git -C "$TREE" fetch --depth 1 origin "$FULLSHA"; then
        echo "WARNING: shallow fetch by sha refused — falling back to a full fetch (multi-GB)"
        git -C "$TREE" fetch origin
    fi
    # -f: discard a previously-applied patch / stale state; build.sh reapplies
    git -C "$TREE" checkout -qf "$FULLSHA"
    at_target "$TREE/.git" || die "checkout landed on $(git -C "$TREE" rev-parse HEAD), expected $SHA"
    echo "checked out $FULLSHA"
fi

step "Module.symvers from the headers package (runbook step 1)"
if [ ! -f "$HERE/$HDRPKG" ]; then
    # Not every kernel ships from jupiter-main: point releases can exist only
    # in a version-branch channel (6.16.12-valve24.4 is only in
    # jupiter-3.8.1x). Probe jupiter-main first, then every other jupiter-*
    # repo the mirror lists. Pin with HDR_REPOS="repo ..." to skip discovery.
    if [ -z "${HDR_REPOS:-}" ]; then
        DISCOVERED=$(curl -fsSL "$MIRROR/" \
            | grep -oE 'href="jupiter-[^"/]*/"' | sed 's|^href="||; s|/"$||' \
            | grep -vxE 'jupiter-(main|ci-test)' | sort -rV | tr '\n' ' ') \
            || DISCOVERED=
        HDR_REPOS="jupiter-main $DISCOVERED"
    fi
    HDR_REPO=
    for repo in $HDR_REPOS; do
        if curl -fsIL -o /dev/null "$MIRROR/$repo/os/x86_64/$HDRPKG"; then
            HDR_REPO=$repo
            break
        fi
    done
    [ -n "$HDR_REPO" ] || die "no jupiter channel on $MIRROR carries $HDRPKG (probed: $HDR_REPOS) — check the mirror indexes by hand"
    echo "found in channel: $HDR_REPO"
    curl -fL -o "$TMPD/$HDRPKG" "$MIRROR/$HDR_REPO/os/x86_64/$HDRPKG" \
        || die "download failed: $MIRROR/$HDR_REPO/os/x86_64/$HDRPKG"
    mv "$TMPD/$HDRPKG" "$HERE/$HDRPKG"
else
    echo "already downloaded: $HDRPKG"
fi
# no -m1: grep quitting at the first match SIGPIPEs tar mid-listing, and
# pipefail turns that into a bogus "no Module.symvers" failure
MEMBER=$(tar --zstd -tf "$HERE/$HDRPKG" | grep '/Module.symvers$') \
    || die "no Module.symvers inside $HDRPKG"
MEMBER=${MEMBER%%$'\n'*}
tar --zstd -xOf "$HERE/$HDRPKG" "$MEMBER" > "$TREE/Module.symvers"
[ -s "$TREE/Module.symvers" ] || die "extracted Module.symvers is empty"
echo "Module.symvers -> $TREE/Module.symvers ($(wc -l < "$TREE/Module.symvers" | tr -d ' ') symbols)"

step "build deps into deps/ (runbook step 2)"
DEPS=$HERE/deps
mkdir -p "$DEPS"
for repo in "${DEP_REPOS[@]}"; do
    curl -fsSL -o "$TMPD/$repo.db" "$MIRROR/$repo/os/x86_64/$repo.db" \
        || die "could not fetch package database for $repo"
done
for pkg in "${DEP_PKGS[@]}"; do
    # exact-name match: a db entry dir is <name>-<ver>-<rel>/, so an entry
    # belongs to $pkg iff stripping the last two -fields leaves exactly $pkg
    # (a naive prefix grep matches openssl-1.1 when you want openssl)
    ENTRY='' REPO=''
    for repo in "${DEP_REPOS[@]}"; do
        ENTRY=$(tar -tf "$TMPD/$repo.db" | sed -n 's|/$||p' \
            | awk -F- -v p="$pkg" 'NF>2 { n=""; for(i=1;i<=NF-2;i++) n=n (i>1?"-":"") $i; if (n==p) { print; exit } }')
        [ -n "$ENTRY" ] && { REPO=$repo; break; }
    done
    [ -n "$ENTRY" ] || die "package '$pkg' not found in: ${DEP_REPOS[*]}"

    if [ -e "$DEPS/.$ENTRY.done" ]; then
        echo "$pkg: $ENTRY already extracted"
        continue
    fi
    FILE=$ENTRY-x86_64.pkg.tar.zst
    if [ ! -f "$HERE/$FILE" ]; then
        # ':' in an epoch (pahole-1:1.30-2) must be %-encoded in the URL
        curl -fL -o "$TMPD/$FILE" "$MIRROR/$REPO/os/x86_64/${FILE//:/%3A}" \
            || die "download failed: $FILE from $REPO"
        mv "$TMPD/$FILE" "$HERE/$FILE"
    fi
    # extract only usr/ — skips .PKGINFO/.MTREE clutter
    SUBTREE=usr
    for h in "${HEADERS_ONLY_PKGS[@]}"; do
        [ "$pkg" = "$h" ] && SUBTREE=usr/include
    done
    tar --zstd -xf "$HERE/$FILE" -C "$DEPS" "$SUBTREE"
    touch "$DEPS/.$ENTRY.done"
    echo "$pkg: $ENTRY extracted from $REPO"
done

step "verify build environment"
# shellcheck source=bc250-audio-fix/build-env.sh
( source "$HERE/build-env.sh" ) || die "build-env.sh still unhappy after dep extraction"
echo "build-env.sh OK (pahole, bc on PATH)"

echo
echo "OK — sources and deps ready for $REL."
echo "Next: $HERE/build.sh"
