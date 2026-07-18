#!/bin/bash
# Remove generated state so the next ./patch-driver.sh starts from a known-clean
# slate — the undo for fetch-sources.sh + build.sh, in two tiers:
#
#   ./clean.sh [kernel-tree]        Build state only: git-clean the kernel
#                                   tree back to pristine source (build
#                                   objects, .config, Module.symvers,
#                                   localversion*, the applied patch) and
#                                   drop build logs. Cached downloads
#                                   (*.pkg.tar.zst, deps/) survive, so the
#                                   next patch-driver.sh refetches nothing big.
#   ./clean.sh --all [kernel-tree]  Also delete the tree + parked .git,
#                                   deps/, downloaded packages, and
#                                   superseded amdgpu-*.ko builds — every
#                                   category .gitignore marks reproducible.
#                                   The next patch-driver.sh refetches (multi-GB).
#
#   -n / --dry-run                  Print what would be removed, remove
#                                   nothing.
#
# Never touches anything git tracks (amdgpu.ko.zst, the patch, scripts).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

die()  { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
run()  { echo "  $*"; [ "$DRY" = 1 ] || "$@"; }

ALL=0 DRY=0 TREE=
for arg; do
    case "$arg" in
        --all)        ALL=1 ;;
        -n|--dry-run) DRY=1 ;;
        -*)           die "unknown flag: $arg (usage: ./clean.sh [--all] [-n] [kernel-tree])" ;;
        *)  [ -z "$TREE" ] || die "more than one kernel-tree argument"
            TREE=$(cd "$arg" 2>/dev/null && pwd) || die "kernel tree not found: $arg" ;;
    esac
done
TREE=${TREE:-$HERE/valve-kernel}
PARKED=$TREE-dot-git

if [ "$ALL" = 1 ]; then
    step "delete kernel tree and parked .git (--all)"
    if [ -e "$TREE" ]; then
        # refuse to rm -rf a directory that isn't recognizably a kernel tree
        grep -q '^VERSION' "$TREE/Makefile" 2>/dev/null \
            || die "$TREE is not a kernel tree — refusing to delete it"
        run rm -rf "$TREE"
    else
        echo "  (absent) $TREE"
    fi
    if [ -e "$PARKED" ]; then run rm -rf "$PARKED"; else echo "  (absent) $PARKED"; fi
elif [ ! -d "$TREE" ]; then
    step "reset kernel tree to pristine source"
    echo "  (absent) $TREE — nothing to clean"
else
    step "reset kernel tree to pristine source"
    # same live-or-parked .git resolution as build.sh
    [ -d "$TREE/.git" ] && [ -d "$PARKED" ] && die "both $TREE/.git and $PARKED exist — resolve by hand first"
    if   [ -d "$TREE/.git" ]; then GITDIR=$TREE/.git
    elif [ -d "$PARKED" ];    then GITDIR=$PARKED
    else die "no .git for $TREE (live or parked at $PARKED) — cannot tell source from build output; --all deletes the whole tree instead"
    fi
    G=(git --git-dir="$GITDIR" --work-tree="$TREE" -C "$TREE")
    if [ "$DRY" = 1 ]; then
        "${G[@]}" clean -xdn
        echo "  (dry-run) would also: git checkout -f -- .   # reverts the applied patch"
    else
        "${G[@]}" clean -xdfq
        "${G[@]}" checkout -qf -- .
        echo "  tree pristine at $("${G[@]}" rev-parse --short HEAD)"
    fi
fi

step "build logs"
FOUND=0
for f in "$HERE"/*.log "$HERE"/summary.txt; do
    [ -e "$f" ] || continue
    run rm -f "$f"; FOUND=1
done
[ "$FOUND" = 1 ] || echo "  (none)"

if [ "$ALL" = 1 ]; then
    step "cached downloads and extracted deps (--all)"
    FOUND=0
    for f in "$HERE"/deps "$HERE"/*.pkg.tar.zst "$HERE"/*.src.tar.gz; do
        [ -e "$f" ] || continue
        run rm -rf "$f"; FOUND=1
    done
    [ "$FOUND" = 1 ] || echo "  (none)"

    step "superseded module builds (--all)"
    # amdgpu-*.ko* only — never amdgpu.ko.zst, the tracked artifact
    FOUND=0
    for f in "$HERE"/amdgpu-*.ko "$HERE"/amdgpu-*.ko.zst; do
        [ -e "$f" ] || continue
        run rm -f "$f"; FOUND=1
    done
    [ "$FOUND" = 1 ] || echo "  (none)"
fi

echo
if [ "$DRY" = 1 ]; then
    echo "dry-run — nothing was removed."
else
    echo "OK — cleaned. Next full cycle: $HERE/patch-driver.sh"
fi
