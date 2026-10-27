# audiohold

A macOS menu bar item (a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin) that shows which apps are holding an audio output open, and gives you one click to free your Bluetooth headphones for another device.

## The problem

Multipoint Bluetooth headphones switch between your phone and your Mac based on which one is using audio. On macOS, an app that merely keeps an audio output open, even one rendering pure silence, is enough to keep the headphones pinned to the Mac. Browsers are a common culprit: a web page with an idle Web Audio context or a WebRTC connection can hold the output for as long as the tab is open, with no speaker icon and nothing in Now Playing.

## What it shows

```
🎧 1                                   <- processes holding an output: red if one is on Bluetooth, orange otherwise, grey for none
Now Playing: <title>, <artist>
Pause (app stays open)                 <- system media pause, only for apps that publish Now Playing
Holding an audio output open:
Firefox (pid 123) on Bluetooth: show app   <- click brings that app to the front
Park audio on speakers (frees headphones)  <- moves the default output to the built-in speakers
Refresh
```

* **Holders** come from CoreAudio's own per-process list (`kAudioHardwarePropertyProcessObjectList`), so any app is covered, including ones that play nothing audible.
* **Pause / Play** sends the system media command through `nowplaying-cli`. It never quits an app. It only reaches apps that publish a Now Playing session, and pausing a video does not close a silent stream some other part of the app keeps open.
* **Park** remembers the current default output (and refuses to run if it cannot read it), then switches the default (and alert sound) output to the built-in speakers. Apps that follow the system default move their streams with it, which releases the headphones. **Unpark** restores the remembered output.

## What it cannot do

macOS only knows which *process* holds audio. Multi-process apps such as browsers relay every tab's audio through one process, so no outside tool can tell which tab is responsible. Clicking a holder brings the app forward; finding the tab is up to you.

Suspending a process does not help either: in testing, a process stopped with SIGSTOP kept its output hold until it exited. Park works because it moves the stream rather than trying to stop it.

On a macOS version without the CoreAudio process list the menu shows no holders at all, which is not the same as none.

## Install

Requirements: a recent macOS with the CoreAudio process object API (developed and tested on macOS 26; Apple documents the related process tap API from macOS 14.2), Xcode command line tools (`swiftc`), Homebrew.

```sh
brew install swiftbar nowplaying-cli
git clone https://github.com/navarro165/audiohold.git
cd audiohold
mkdir -p ~/.local/bin
swiftc -O audioroute.swift -o ~/.local/bin/audioroute
mkdir -p ~/SwiftBarPlugins
cp audiohold.5s.sh ~/SwiftBarPlugins/
chmod +x ~/SwiftBarPlugins/audiohold.5s.sh
```

Then open SwiftBar and choose `~/SwiftBarPlugins` as its plugin folder. The `5s` in the file name is the refresh interval.

### Settings

Change a setting by editing the defaults at the top of `audiohold.5s.sh`, or by exporting the variable from your login profile (`~/.zprofile` with SwiftBar's default zsh shell); SwiftBar runs plugins in a login shell, so interactive-only shell config is not read:

| Variable | Default | Meaning |
|---|---|---|
| `AUDIOHOLD_AUDIOROUTE` | `~/.local/bin/audioroute` | Path to the compiled helper |
| `AUDIOHOLD_PARK_UID` | `BuiltInSpeakerDevice` | Device UID to park on. Run `audioroute list` to see every output device and its UID. Macs without built-in speakers need this set |

The remembered output for Unpark is stored in `~/Library/Application Support/audiohold/previous-output-uid`. It is forgotten after Unpark (even if that device is gone) and when you pick another output yourself.

## The helper

`audioroute` is a single Swift file with no dependencies:

```sh
audioroute status          # default output, then every process running output and its device UIDs
audioroute list            # every device that has an output, with its UID
audioroute set <UID>       # set the default and alert-sound output to a device
```

## Security notes

* The plugin makes no network requests. It runs `audioroute`, `nowplaying-cli`, `ps`, `open` and standard shell utilities, and stores one device UID on disk.
* Now Playing titles, app paths and device names come from other software (web pages control Now Playing titles). Before printing them the plugin drops invalid UTF-8, removes control and line-separator characters, and replaces `|`, so they cannot add menu rows or inject SwiftBar actions such as `shell=` or `href=`. An app whose path cannot be printed safely is listed without the click action.
* SwiftBar registers a `swiftbar://` URL scheme that can download and install plugins from a link. Your browser asks before opening one; do not tick "always allow" for it.

## License

MIT
