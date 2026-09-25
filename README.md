# v2s

<p align="center">
  <img src="Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="v2s app icon" width="256" height="256">
</p>

<p align="center">
  <strong>Live bilingual subtitles for meetings, calls, streams, and videos on macOS.</strong>
</p>

<p align="center">
  v2s turns microphone input or app audio into a clean two-line subtitle bar so you can follow speech in one language and read it in another without leaving the screen you are already using.
</p>

<p align="center">
  <a href="https://franklioxygen.github.io/v2s/">Website</a>
  ·
  <a href="README.zh-CN.md">中文文档</a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/b65167ee-ae7e-4e37-8316-ebd200ae89a7" alt="Mar-20-2026 11-08-59">
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/449039ee-c329-426e-a55b-ab6660c56ca7" alt="Screenshot 2026-03-25 at 1 10 39 PM" width="500">
</p>

## Why v2s

- Follow live conversations with translated subtitles pinned at the top of your screen.
- Capture from your microphone or from a specific macOS app instead of your entire system mix.
- Keep the original speech and the translated line visible together for fast context switching.
- Stay in a lightweight menu bar workflow instead of juggling browser tabs or full-screen caption apps.

## Features

- Menu bar app built for always-available subtitle access.
- Live subtitle overlay with translated text on the first line and source text on the second.
- Audio source selection for microphones and running macOS apps.
- Speech transcription powered by Apple's Speech frameworks, preferring on-device recognition.
- On-device translation powered by Apple Translation.
- Transcript summarization powered by Apple Intelligence, falling back to an on-device extractive summary when Apple Intelligence is unavailable.
- Overlay styling controls so the subtitle bar stays readable on top of real work.

## Input and Subtitle Languages

v2s asks Apple's Speech and Translation frameworks which languages the current Mac supports, so the choices automatically follow OS and model updates. Regional variants are collapsed in the UI, while meaningful script variants such as Simplified and Traditional Chinese remain separate. Apple Translation availability is also checked for each source/destination pair before a session starts.

## Privacy

- No account, cloud backend, analytics, or telemetry.
- v2s has no cloud backend and does not send audio or subtitle text to its own servers.
- Translation uses Apple's on-device Translation framework. Some language packs may need to be downloaded first through System Settings.
- Speech recognition prefers Apple's on-device models, and v2s picks a language variant that has a local model whenever one exists.
- Some languages have no on-device model on a given Mac — this is common on Intel Macs, and for languages outside the modern Speech stack. Those run through Apple's server-based recognition, which needs a network connection, is subject to Apple's service quotas, and sends captured speech to Apple under Apple's privacy terms.
- Voice activity detection runs the [Silero VAD](THIRD_PARTY_NOTICES.md) model through Apple's system Core ML framework; v2s bundles no third-party inference runtime, and the [conversion is reproducible](scripts/convert_silero_vad_coreml.py).

## Getting Started

### Install with Homebrew

```bash
brew install --cask franklioxygen/v2s/v2s
```

v2s is not notarized by Apple yet, so macOS quarantines it after download. Clear
the flag once, then launch the app:

```bash
xattr -dr com.apple.quarantine /Applications/v2s.app
```

If you already have `v2s.app` in your Applications folder from a manual install,
add `--adopt` so Homebrew takes over the existing copy instead of refusing to
overwrite it.

Updates arrive through the in-app updater. To let Homebrew handle them instead,
run `brew upgrade --cask --greedy v2s`.

### Install manually

1. Download the latest `.app.zip` from [Releases](https://github.com/franklioxygen/v2s/releases).
2. Unzip and move `v2s.app` to your Applications folder.

### First run

1. Launch v2s — it appears as an icon in your menu bar.
2. Select an input source (a running app or microphone).
3. Choose your input and subtitle languages.
4. Click **Start**.

v2s will ask for permissions on first use:

- **Speech Recognition** — to transcribe audio into text.
- **Microphone** — when using a microphone as the input source.
- **Audio Capture** — when capturing audio from another app.

## Requirements

- Speech transcription and translation require macOS 26 or newer
- Apple silicon and Intel Macs are supported. Which speech languages are available, and whether they recognize on device, depends on the Mac and the selected language.

## Building from Source

```bash
git clone https://github.com/franklioxygen/v2s.git
cd v2s
open v2s.xcodeproj
```

Or from the terminal:

```bash
xcodebuild -project v2s.xcodeproj -scheme v2s -configuration Debug build
```

To build specifically for an Intel Mac:

```bash
swift build -c release --arch x86_64
```

### Building for daily use (keeps the audio permission)

```bash
scripts/run-local.sh
```

This builds v2s, signs it with your **Apple Development** certificate, installs it to
`~/Applications`, and launches it with `open`. Use it instead of running from Xcode when you
want app audio capture to keep working across rebuilds:

- Debug builds from the project are signed ad hoc. macOS ties the *Screen & System Audio
  Recording* permission to the app's code signature, and an ad-hoc signature changes on every
  rebuild, so the old permission stops applying. Core Audio then delivers pure silence without
  reporting an error.
- An app started from Xcode (⌘R) or a terminal is checked against **Xcode's/Terminal's**
  permission, not v2s's. `open` makes v2s responsible for its own permission.

Run the tests with:

```bash
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme v2s \
  -destination 'platform=macOS' COREML_CODEGEN_LANGUAGE=Swift
```

## Troubleshooting: no subtitles from Google Meet / a browser

Open the menu bar popover while the session runs. The **Audio** card shows a live level meter
and what v2s hears:

| Status | Meaning | What to do |
| --- | --- | --- |
| Hearing audio | Audio arrives | — |
| Connected — app is silent | The app is not playing sound yet (e.g. Meet lobby) | Join the meeting or unmute the speaker. v2s keeps waiting; it no longer restarts itself in a loop. |
| Reconnecting audio… | The audio route changed (Bluetooth headset, browser audio process restarted) | Nothing; v2s rebuilds only the audio tap and keeps the recognizer running. |
| No audio — check permission | The app is playing but v2s only receives silence | Click **Open Audio Recording Settings**, enable v2s under *System Audio Recording Only*, then restart v2s. If you rebuilt v2s, use `scripts/run-local.sh`. |

Bluetooth headsets: capture no longer uses the output device as its clock, so switching a
headset between music (A2DP) and call (HFP) mode, or connecting it mid-meeting, does not stop
capture.

## License

MIT
