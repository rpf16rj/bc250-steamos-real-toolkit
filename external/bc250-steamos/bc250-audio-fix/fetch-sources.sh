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
#      version branch like jupiter-3.8.1x instead of jupiter-main). If Valve
#      never published those headers, build.sh generates Module.symvers by
#      building the exact source completely for AMDGPU. The WiFi preparation
#      mode can omit it when CONFIG_MODVERSIONS is disabled.
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
HEADER_FETCHER=$HERE/../fetch-steamos-package.sh

# Keep cross-host source fetching possible with KERNEL_RELEASE, but make the
# documented on-device command self-sufficient after a SteamOS update.
if [ -r /proc/config.gz ]; then
    "$HERE/ensure-build-prereqs.sh"
fi

MIRROR=${MIRROR:-https://steamdeck-packages.steamos.cloud/archlinux-mirror}
KERNEL_REMOTE=${KERNEL_REMOTE:-https://github.com/Evlav/linux-integration.git}
KERNEL_API=${KERNEL_API:-https://api.github.com/repos/Evlav/linux-integration}
DEP_PKGS=(pahole bc libelf openssl zlib glibc linux-api-headers bison flex cpio gettext perl python)
# SteamOS 3.9 strips /usr/include from the image, so HOSTCC can't find even
# sys/types.h. The libraries themselves (libc.so, crt*.o) are still installed,
# so for these two packages only usr/include is extracted — pulling glibc's
# usr/lib into deps/ would shadow the system libc via LD_LIBRARY_PATH.
HEADERS_ONLY_PKGS=(glibc linux-api-headers)
DEP_REPOS=(extra-main core-main)

die()  { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[ -f "$HEADER_FETCHER" ] || die "SteamOS package fetcher missing: $HEADER_FETCHER"

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
managed_tree() { [ "$TREE" = "$HERE/valve-kernel" ] || [ -f "$TREE/.bc250-managed-tree" ]; }
tree_clean() { git --git-dir="$1" --work-tree="$TREE" diff --quiet HEAD -- .; }
check_owner() {
    local path=$1 owner
    [ -e "$path" ] || return 0
    owner=$(stat -c '%u' "$path") || die "could not determine ownership of $path"
    [ "$owner" = "$(id -u)" ] \
        || die "$path is not owned by $(id -un); rerun the root AIC8800 setup to repair the managed cache, or restore its ownership manually"
}

check_owner "$TREE"
check_owner "$TREE/.git"
check_owner "$PARKED"

if [ -d "$PARKED" ] && at_target "$PARKED"; then
    echo "tree already at $SHA (.git parked) — nothing to do"
elif [ -d "$TREE/.git" ] && at_target "$TREE/.git"; then
    echo "tree already at $SHA — nothing to do"
else
    if [ -d "$PARKED" ]; then
        # parked but at the wrong commit (SteamOS updated) — unpark to fetch;
        # build.sh re-parks
        tree_clean "$PARKED" || managed_tree \
            || die "$TREE has tracked changes and is not toolkit-managed; refusing to discard them during the kernel update"
        [ -d "$TREE/.git" ] && die "both $TREE/.git and $PARKED exist — resolve by hand first"
        mv "$PARKED" "$TREE/.git"
        echo "unparked $PARKED -> $TREE/.git"
    fi
    if [ -d "$TREE/.git" ]; then
        tree_clean "$TREE/.git" || managed_tree \
            || die "$TREE has tracked changes and is not toolkit-managed; refusing to discard them during checkout"
    fi
    if [ ! -d "$TREE/.git" ]; then
        [ -e "$TREE" ] && [ -n "$(ls -A "$TREE" 2>/dev/null)" ] \
            && die "$TREE exists without .git — cannot verify its commit; move it aside"
        mkdir -p "$TREE"
        git -C "$TREE" init -q
        git -C "$TREE" remote add origin "$KERNEL_REMOTE"
        touch "$TREE/.bc250-managed-tree"
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
FULL_BUILD_REQUIRED=$TREE/.bc250-full-build-required
MIRROR="$MIRROR" HDR_REPOS="${HDR_REPOS:-}" \
    bash "$HEADER_FETCHER" "$HDRPKG" "$HERE/$HDRPKG" && HEADER_STATUS=0 \
    || HEADER_STATUS=$?
if [ "$HEADER_STATUS" = 0 ]; then
    MEMBER=usr/lib/modules/$REL/build/Module.symvers
    tar --zstd -xOf "$HERE/$HDRPKG" "$MEMBER" > "$TMPD/Module.symvers" \
        || die "no $MEMBER inside $HDRPKG"
    [ -s "$TMPD/Module.symvers" ] || die "extracted Module.symvers is empty"
    mv "$TMPD/Module.symvers" "$TREE/Module.symvers"
    rm -f "$FULL_BUILD_REQUIRED" "$TREE/.bc250-full-build-stamp" "$TREE/.bc250-full-build-in-progress"
    echo "Module.symvers -> $TREE/Module.symvers ($(wc -l < "$TREE/Module.symvers" | tr -d ' ') symbols)"
elif [ "$HEADER_STATUS" = 3 ]; then
    printf '%s\n' "$REL" > "$FULL_BUILD_REQUIRED"
    echo "WARNING: Valve has not published $HDRPKG."
    echo "         AMDGPU will build the exact kernel for Module.symvers; WiFi may use source-only preparation."
else
    die "could not reliably retrieve the matching kernel headers"
fi

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
        # Consume the complete tar listing: exiting awk on the first match
        # SIGPIPEs tar, which is fatal under pipefail.
        ENTRY=$(tar -tf "$TMPD/$repo.db" | sed -n 's|/$||p' \
            | awk -F- -v p="$pkg" 'NF>2 { n=""; for(i=1;i<=NF-2;i++) n=n (i>1?"-":"") $i; if (n==p && !found) { print; found=1 } }')
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

step "verify complete build environment"
# shellcheck source=bc250-audio-fix/build-env.sh
( source "$HERE/build-env.sh" ) || die "build-env.sh still unhappy after dep extraction"
echo "build-env.sh OK (compiler, Kbuild tools, libraries, and packaging tools available)"

echo
echo "OK — sources and deps ready for $REL."
echo "Next: $HERE/build.sh"
