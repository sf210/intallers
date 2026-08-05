#!/bin/bash

set -euo pipefail

# Install/upgrade Neovim system-wide from the official prebuilt tarball
# Usage: nvim_install.sh VERSION (e.g. nvim_install 0.12.4)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ver=${1:-}
[ -n "$ver" ] || die "usage: $0 VERSION (e.g. $0 0.12.4)"

for cmd in curl jq sha256sum tar; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

tarball="nvim-linux-x86_64.tar.gz"
url="https://github.com/neovim/neovim/releases/download/v$ver/$tarball"

# Neovim ships no .sha256sum asset; the checksum lives in the release metadata.
sha=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/tags/v$ver" \
      | jq -r --arg n "$tarball" '.assets[] | select(.name==$n) | .digest' \
      | cut -d: -f2) \
      || die "could not fetch release metadata for v$ver - does that version exist?"
[ -n "$sha" ] || die "no checksum published for $tarball in release v$ver"

# Private temp dir, removed on any exit. Replaces `cd /tmp`.
tmp=$(mktemp -d) || die "could not create temp dir"
trap 'rm -rf "$tmp"' EXIT

oldver=""
command -v nvim >/dev/null 2>&1 && oldver=$(nvim --version | sed -n '1s/^NVIM v//p')
[ "$oldver" != "$ver" ] || die "v$ver is already installed"

curl -fL --proto '=https' -o "$tmp/$tarball" "$url" \
    || die "download failed - does v$ver exist? $url"

actual=$(sha256sum "$tmp/$tarball" | awk '{print $1}')
[ -n "$actual" ] || die "sha256sum produced no output"
[ "$actual" = "$sha" ] || die "checksum mismatch
  expected: $sha
  actual:   $actual"
echo "checksum OK"

# One-time migration off the old unversioned layout.
if [ -d /opt/nvim-linux-x86_64 ]; then
    [ -n "$oldver" ] || die "cannot determine version of /opt/nvim-linux-x86_64"
    sudo mv /opt/nvim-linux-x86_64 "/opt/nvim-$oldver"
fi
[ -e "/opt/nvim-$ver" ] && die "/opt/nvim-$ver already exists - remove it first"

# Extract as yourself, then move into place. No sudo tar, no name collision.
tar -C "$tmp" -xzf "$tmp/$tarball"
[ -d "$tmp/nvim-linux-x86_64" ] || die "unexpected tarball layout"
sudo mv "$tmp/nvim-linux-x86_64" "/opt/nvim-$ver"
sudo chown -R root:root "/opt/nvim-$ver"

sudo ln -sfn "/opt/nvim-$ver" /opt/nvim
sudo ln -sfn /opt/nvim/bin/nvim /usr/local/bin/nvim

# mkdir -p is already a no-op when these exist - no check needed.
sudo mkdir -p /usr/local/share/man/man1 /usr/local/share/applications
sudo ln -sfn /opt/nvim/share/man/man1/nvim.1 /usr/local/share/man/man1/nvim.1
sudo ln -sfn /opt/nvim/share/applications/nvim.desktop /usr/local/share/applications/nvim.desktop

hash -r
echo "installed: $(/usr/local/bin/nvim --version | sed -n 1p)"

if [ -n "$oldver" ]; then
    echo "rollback: sudo ln -sfn /opt/nvim-$oldver /opt/nvim"
fi

