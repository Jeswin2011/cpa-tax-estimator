#!/bin/sh
# CPA Tax Estimator installer for macOS (Apple Silicon) and Linux (x86_64).
#   curl -fsSL https://jeswin2011.github.io/cpa-tax-estimator/install.sh | sh
# Downloads the latest release from GitHub, checks its SHA-256, and installs it for the current user.
set -eu

REPO="Jeswin2011/cpa-tax-estimator"
APP="CPA Tax Estimator"

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "'$1' is required but not installed."; }

need curl
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin)
    [ "$arch" = "arm64" ] || fail "only Apple Silicon Macs (M1 or newer) are supported right now."
    ext='\.dmg' ;;
  Linux)
    [ "$arch" = "x86_64" ] || fail "only 64-bit Intel/AMD Linux (x86_64) is supported right now."
    ext='\.AppImage' ;;
  *) fail "this installer is for macOS and Linux. On Windows run: irm https://jeswin2011.github.io/cpa-tax-estimator/install.ps1 | iex" ;;
esac

say "Finding the latest version of $APP..."
release=$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest") \
  || fail "could not reach GitHub. Check your internet connection."
# Parse without jq. In each asset, "digest" comes before "browser_download_url" with only plain
# values (no braces) between them, so one match ties a file to its checksum.
flat=$(printf '%s' "$release" | tr -d '\n\r')
match=$(printf '%s' "$flat" | grep -oE "\"digest\": *\"sha256:[0-9a-f]+\"[^{}]*\"browser_download_url\": *\"[^\"]+$ext\"" | head -n 1 || true)
[ -n "$match" ] || match=$(printf '%s' "$flat" | grep -oE "\"browser_download_url\": *\"[^\"]+$ext\"" | head -n 1 || true)
url=$(printf '%s' "$match" | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
digest=$(printf '%s' "$match" | grep -oE 'sha256:[0-9a-f]+' | cut -d: -f2 || true)
version=$(printf '%s' "$flat" | grep -oE '"tag_name": *"[^"]+"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$url" ] || fail "no download for your system was found in the latest release."
name=${url##*/}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
say "Downloading $name ($version)..."
curl -fL --progress-bar -o "$tmp/$name" "$url" || fail "download failed."

if [ -n "$digest" ]; then
  if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
  else actual=$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1); fi
  [ "$actual" = "$digest" ] || fail "the download's checksum doesn't match GitHub's. Nothing was installed."
  say "Checksum verified."
else
  say "Warning: GitHub did not publish a checksum for this file, so it could not be verified."
fi

if [ "$os" = "Darwin" ]; then
  need hdiutil
  dest=/Applications
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  hdiutil attach "$tmp/$name" -nobrowse -quiet -mountpoint "$tmp/mnt" || fail "could not open the disk image."
  rm -rf "$dest/$APP.app"
  cp -R "$tmp/mnt/$APP.app" "$dest/" || { hdiutil detach "$tmp/mnt" -quiet; fail "could not copy the app to $dest."; }
  hdiutil detach "$tmp/mnt" -quiet
  say ""
  say "Installed $APP $version to $dest/$APP.app"
  say "Open it from Launchpad or run: open \"$dest/$APP.app\""
else
  dir="$HOME/.local/share/cpa-tax-estimator"
  bin="$HOME/.local/bin"
  mkdir -p "$dir" "$bin" "$HOME/.local/share/applications"
  mv "$tmp/$name" "$dir/CPA-Tax-Estimator.AppImage"
  chmod +x "$dir/CPA-Tax-Estimator.AppImage"
  ln -sf "$dir/CPA-Tax-Estimator.AppImage" "$bin/cpa-tax-estimator"
  curl -fsSL -o "$dir/icon.png" "https://jeswin2011.github.io/cpa-tax-estimator/icon.png" || true
  cat > "$HOME/.local/share/applications/cpa-tax-estimator.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP
Comment=Sort business transactions and estimate federal tax
Exec="$dir/CPA-Tax-Estimator.AppImage" %U
Icon=$dir/icon.png
Categories=Office;Finance;
Terminal=false
EOF
  say ""
  say "Installed $APP $version to $dir"
  say "Open it from your app menu, or run: cpa-tax-estimator"
  case ":$PATH:" in *":$bin:"*) ;; *) say "(Add $bin to your PATH to use the cpa-tax-estimator command.)" ;; esac
  if ! ldconfig -p 2>/dev/null | grep -q libfuse.so.2; then
    say "Note: AppImages need FUSE 2. If the app doesn't open, install it (Ubuntu/Debian: sudo apt install libfuse2t64 or libfuse2)."
  fi
fi
