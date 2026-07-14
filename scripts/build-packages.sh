#!/usr/bin/env bash
# Build all FarmNerdOS PKGBUILDs and assemble the [farmnerdos] pacman repo.
# Run as a normal user on an Arch host with base-devel installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT/repo/x86_64"
REPO_NAME="farmnerdos"

command -v makepkg >/dev/null || { echo "error: makepkg not found (install base-devel)"; exit 1; }
command -v repo-add >/dev/null || { echo "error: repo-add not found (install pacman)"; exit 1; }
[[ $EUID -eq 0 ]] && { echo "error: run as a normal user, not root (makepkg refuses root)"; exit 1; }

mkdir -p "$REPO_DIR"

for pkg in "$ROOT"/packages/*/; do
    [[ -f "$pkg/PKGBUILD" ]] || continue
    echo "==> building $(basename "$pkg")"
    # -d: skip runtime-dep checks — deps (calamares, plasma) live in repos the
    # build host doesn't have; they're resolved at install time inside the ISO
    ( cd "$pkg" && makepkg -dCcf --noconfirm --skipinteg )
    mv "$pkg"/*.pkg.tar.zst "$REPO_DIR/"
done

echo "==> generating repo database"
repo-add --new --remove "$REPO_DIR/$REPO_NAME.db.tar.gz" "$REPO_DIR"/*.pkg.tar.zst

echo "==> done: [farmnerdos] repo at $REPO_DIR"
