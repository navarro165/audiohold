#!/bin/bash
# Installs or updates audiohold: the audioroute helper built from source into ~/.local/bin, SwiftBar and
# nowplaying-cli from Homebrew, and the plugin copied into SwiftBar's plugin folder. Safe to re-run.
set -euo pipefail

say() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Resolve the script's real directory, following symlinks (macOS readlink has no -f before 12.3).
self="$0"
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
SRC="$(CDPATH='' cd "$(dirname "$self")" && pwd -P)"

BIN="$HOME/.local/bin"
DEFAULT_PLUGIN_DIR="$HOME/SwiftBarPlugins"
BACKUP_DIR="$HOME/Library/Application Support/audiohold"

# Everything that can fail cheaply is checked before anything is installed.
[ "$(id -u)" -ne 0 ] || die "do not run as root; run as the user whose menu bar should show audiohold."
[ "$(uname -s)" = "Darwin" ] || die "audiohold only runs on macOS."
[ -f "$SRC/audioroute.swift" ] && [ -f "$SRC/audiohold.5s.sh" ] \
  || die "run this from a clone of the repo (audioroute.swift and audiohold.5s.sh not found in $SRC)."
xcode-select -p >/dev/null 2>&1 || die "the Xcode command line tools are required; install them first."
command -v swiftc >/dev/null 2>&1 || die "swiftc not found; install the Xcode command line tools."
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
fi
command -v brew >/dev/null 2>&1 || die "Homebrew is required: https://brew.sh"

say "Building audioroute into $BIN"
mkdir -p "$BIN"
swiftc -O "$SRC/audioroute.swift" -o "$BIN/audioroute.new"
mv -f "$BIN/audioroute.new" "$BIN/audioroute"

if open -Ra SwiftBar >/dev/null 2>&1; then
  say "SwiftBar already installed"
else
  say "Installing SwiftBar"
  brew install swiftbar
fi

if brew list nowplaying-cli >/dev/null 2>&1 || command -v nowplaying-cli >/dev/null 2>&1; then
  say "nowplaying-cli already installed"
else
  say "Installing nowplaying-cli"
  brew install nowplaying-cli
fi

# Reuse the folder SwiftBar already watches; otherwise point it at a new one.
plugin_dir=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
pref_changed=0
if [ -z "$plugin_dir" ]; then
  plugin_dir="$DEFAULT_PLUGIN_DIR"
  pref_changed=1
fi
case "$plugin_dir" in "~"|"~/"*) plugin_dir="$HOME${plugin_dir#\~}" ;; esac
case "$plugin_dir" in
  *$'\n'*) die "SwiftBar's PluginDirectory setting is not a single path; set the folder in SwiftBar first." ;;
  /*) ;;
  *) die "SwiftBar's PluginDirectory is not an absolute path ($plugin_dir); set the folder in SwiftBar first." ;;
esac

dest="$plugin_dir/audiohold.5s.sh"
say "Installing the plugin into $plugin_dir"
mkdir -p "$plugin_dir"
if [ -e "$dest" ] && [ "$(cd "$(dirname "$dest")" && pwd -P)/$(basename "$dest")" = "$SRC/audiohold.5s.sh" ]; then
  say "Plugin folder is this repo; nothing to copy"
else
  if [ -f "$dest" ] && ! cmp -s "$dest" "$SRC/audiohold.5s.sh"; then
    # Keep a customised plugin; the backup lives outside the plugin folder so SwiftBar does not load it.
    mkdir -p "$BACKUP_DIR"
    backup="$BACKUP_DIR/audiohold.5s.sh.$(date +%Y%m%d-%H%M%S).bak"
    cp "$dest" "$backup" && chmod 644 "$backup"
    say "Your previous plugin differed; saved it to $backup"
  fi
  # Remove first so a symlink at the destination is replaced, not written through.
  rm -f "$dest"
  cp "$SRC/audiohold.5s.sh" "$dest"
  chmod 755 "$dest"
fi
if [ "$pref_changed" = 1 ]; then
  defaults write com.ameba.SwiftBar PluginDirectory -string "$plugin_dir"
fi

if [ "$pref_changed" = 1 ] && pgrep -x SwiftBar >/dev/null 2>&1; then
  say "Restarting SwiftBar so it picks up the plugin folder"
  osascript -e 'quit app "SwiftBar"' >/dev/null 2>&1 || true
  sleep 2
fi
open -a SwiftBar

say "Done. The 🎧 item appears in the menu bar within a few seconds."
say "To start SwiftBar at login, enable Launch at Login in its preferences."
case ":$PATH:" in *":$BIN:"*) ;; *) say "Tip: add $BIN to PATH to run audioroute directly." ;; esac
