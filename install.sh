#!/usr/bin/env bash
# Build the Rust backend and install the plugin into Omarchy.
set -euo pipefail

PLUGIN_ID="io.github.alexmrtr.oma-channel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v cargo >/dev/null 2>&1 || { echo "error: cargo (Rust) is required — https://rustup.rs" >&2; exit 1; }
command -v omarchy >/dev/null 2>&1 || { echo "error: omarchy CLI not found" >&2; exit 1; }

echo "==> Building Rust backend (release)..."
(cd "$SCRIPT_DIR" && cargo build --release)

echo "==> Placing backend binary..."
mkdir -p "$SCRIPT_DIR/bin" "$HOME/.local/bin"
cp "$SCRIPT_DIR/target/release/oma-channel" "$SCRIPT_DIR/bin/oma-channel"
cp "$SCRIPT_DIR/target/release/oma-channel" "$HOME/.local/bin/oma-channel"

echo "==> Validating plugin manifest..."
omarchy plugin validate "$SCRIPT_DIR"

if omarchy plugin list 2>/dev/null | grep -q "$PLUGIN_ID"; then
  echo "==> Plugin already installed — updating in place."
else
  echo "==> Installing plugin from $SCRIPT_DIR ..."
  if omarchy plugin add "$SCRIPT_DIR" --enable --yes 2>/dev/null; then
    :
  else
    echo "==> Local add not supported; installing via git remote instead."
    echo "    Push this repo to GitHub, then run:"
    echo "      omarchy plugin add <your-git-url> --enable"
    exit 0
  fi
fi

echo "==> Reloading shell..."
omarchy-restart-shell 2>/dev/null || true

echo "Done! The Oma Channel icon (󰑫) should appear in your bar."
