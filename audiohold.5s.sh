#!/bin/bash
# <swiftbar.title>audiohold</swiftbar.title>
# <swiftbar.desc>Shows which apps hold an audio output open, and frees Bluetooth headphones for another device.</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# Shows every process CoreAudio reports as running audio output, and on which device. An app that keeps
# an output open (even rendering silence) can keep multipoint Bluetooth headphones pinned to this Mac.
# Pause sends the system media pause command, so the app stays open and can play again.
# Park moves the default output to the built-in speakers so the headphones are free for another device;
# Unpark restores whatever output was the default before parking.
# Clicking a holder only brings its app to the front: macOS cannot see inside an app (for example tabs).

AR="${AUDIOHOLD_AUDIOROUTE:-$HOME/.local/bin/audioroute}"
PARK_UID="${AUDIOHOLD_PARK_UID:-BuiltInSpeakerDevice}"
STATE_DIR="$HOME/Library/Application Support/audiohold"
STATE_FILE="$STATE_DIR/previous-output-uid"

NP=$(command -v nowplaying-cli || ls /opt/homebrew/bin/nowplaying-cli /usr/local/bin/nowplaying-cli 2>/dev/null | head -n 1)

current_default() { "$AR" status 2>/dev/null | awk -F'\t' '$1=="default"{print $2}'; }

# Text from other software (web page titles, app paths, device names) is printed into SwiftBar menu lines.
# SwiftBar splits lines on any newline-like character and parameters on "|", so remove the former and
# replace the latter, or a hostile string could add rows or inject actions such as shell= or href=.
# Invalid UTF-8 is dropped first: SwiftBar blanks the menu on it, and stray bytes could rejoin into a
# line separator once the separators themselves are removed.
clean() {
  printf '%s' "$1" | iconv -c -f UTF-8 -t UTF-8 | LC_ALL=C tr -d '\000-\037\177' \
    | LC_ALL=C sed -e $'s/\xc2\x85//g' -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g' -e 's/|/¦/g'
}

case "$1" in
  park)
    prev=$(current_default)
    # Never move the output without knowing how to put it back.
    { [ -z "$prev" ] || [ "$prev" = "?" ]; } && exit 1
    [ "$prev" = "$PARK_UID" ] && exit 0
    mkdir -p "$STATE_DIR" && printf '%s\n' "$prev" > "$STATE_FILE" || exit 1
    if ! "$AR" set "$PARK_UID"; then
      # A failed or half-applied switch is rolled back so the menu never claims a park that did not happen.
      "$AR" set "$prev"
      rm -f "$STATE_FILE"
      exit 1
    fi
    exit 0 ;;
  unpark)
    [ -f "$STATE_FILE" ] || exit 1
    prev=$(head -n 1 "$STATE_FILE")
    # Forget the state even if the device is gone (headphones off, reboot), so Park is offered again.
    rm -f "$STATE_FILE"
    [ -n "$prev" ] || exit 1
    exec "$AR" set "$prev" ;;
esac

if [ ! -x "$AR" ]; then
  echo "🎧 ? | color=#8e8e93"
  echo "---"
  echo "audioroute helper not found at $AR | disabled=true"
  exit 0
fi

status=$("$AR" status 2>/dev/null)
# Lines of "pid|device-UID[,UID...]" from CoreAudio's own per-process list, so any app is covered.
holds=$(echo "$status" | awk -F'\t' '$1=="output"{print $2 "|" $4}')
bt=$(echo "$holds" | grep -c -E '([0-9A-F]{2}-){5}[0-9A-F]{2}')

title=""; artist=""; rate=""
if [ -n "$NP" ]; then
  { read -r title; read -r artist; read -r rate; } < <("$NP" get title artist playbackRate 2>/dev/null)
fi
[ "$title" = "null" ] && title=""
[ "$artist" = "null" ] && artist=""
title=$(clean "$title")
artist=$(clean "$artist")

if [ -z "$holds" ]; then
  echo "🎧 | color=#8e8e93"
elif [ "$bt" -gt 0 ]; then
  echo "🎧 $(echo "$holds" | wc -l | tr -d ' ') | color=#ff453a"
else
  echo "🎧 $(echo "$holds" | wc -l | tr -d ' ') | color=#ff9f0a"
fi
echo "---"

if [ -z "$NP" ]; then
  echo "Install nowplaying-cli for Pause and Play | disabled=true"
elif [ -n "$title" ]; then
  echo "Now Playing: $title${artist:+, $artist} | disabled=true"
  if [ "$rate" = "0" ] || [ "$rate" = "null" ]; then
    echo "Play | shell=\"$NP\" param1=play terminal=false refresh=true"
  else
    echo "Pause (app stays open) | shell=\"$NP\" param1=pause terminal=false refresh=true"
  fi
else
  echo "Nothing registered as Now Playing | disabled=true"
fi
echo "---"

if [ -z "$holds" ]; then
  echo "No app holds an audio output"
else
  echo "Holding an audio output open:"
  while IFS='|' read -r pid dev; do
    path=$(ps -o comm= -p "$pid" 2>/dev/null)
    [ -z "$path" ] && continue
    # A relative path starting with "-" would be read as an option by basename and open.
    case "$path" in /*) ;; *) path="./$path" ;; esac
    case "$path" in
      *.app/*) app="${path%%.app/*}.app"; name=$(basename "$app" .app) ;;
      *) app=""; name=$(basename "$path") ;;
    esac
    name=$(clean "$name")
    if echo "$dev" | grep -q -E '([0-9A-F]{2}-){5}[0-9A-F]{2}'; then
      label="Bluetooth"
    elif [ "$dev" = "BuiltInSpeakerDevice" ]; then
      label="built-in speakers"
    else
      label=$(clean "$dev")
    fi
    # Only offer the click when the path is printable as-is; a quote, "|" or control character would
    # break SwiftBar's quoting of the open command.
    if [ -n "$app" ] && [ "$(clean "$app")" = "$app" ] && [[ "$app" != *'"'* ]]; then
      echo "$name (pid $pid) on $label: show app | shell=/usr/bin/open param1=-a param2=\"$app\" terminal=false"
    else
      echo "$name (pid $pid) on $label | disabled=true"
    fi
  done <<< "$holds"
  [ -z "$title" ] && echo "No Now Playing session, so Pause cannot reach the holder | disabled=true"
fi
echo "---"

defdev=$(echo "$status" | awk -F'\t' '$1=="default"{print $2}')
# A parked state is stale once the user picks another output by hand. An unreadable default (empty or
# "?") is a helper hiccup, not a choice, so it keeps the state.
if [ -f "$STATE_FILE" ] && [ -n "$defdev" ] && [ "$defdev" != "?" ] && [ "$defdev" != "$PARK_UID" ]; then
  rm -f "$STATE_FILE"
fi
if [ -f "$STATE_FILE" ]; then
  echo "Parked on $PARK_UID (headphones free for other devices) | disabled=true"
  echo "Unpark: restore previous output | shell=\"$0\" param1=unpark terminal=false refresh=true"
elif [ "$defdev" = "$PARK_UID" ]; then
  echo "Output is already $PARK_UID | disabled=true"
else
  echo "Park audio on speakers (frees headphones) | shell=\"$0\" param1=park terminal=false refresh=true"
fi
echo "---"
echo "Refresh | refresh=true"
