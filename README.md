# SoundEnhancer

A macOS menu-bar app that adds real-time DSP to system audio through a native
virtual audio device. It provides stereo widening, bass/treble EQ, spatial
mixing, and crosstalk cancellation (XTC) for speakers.

## How it works

SoundEnhancer installs a CoreAudio **AudioServerPlugIn** (HAL) driver that
publishes a virtual audio device. Audio routed to that device is processed
inside `coreaudiod` and forwarded to your chosen physical output device — so
there's no "microphone in use" indicator, and no separate audio stream opened by
the app.

- `SoundEnhancer.app` — SwiftUI menu-bar app for configuration and control.
- `SoundEnhancerDriver.driver` — C HAL plug-in (derived from
  [BlackHole](https://github.com/ExistentialAudio/BlackHole)) that does the DSP.

## Requirements

- macOS 14.0 or later (Apple Silicon or Intel)
- Xcode Command Line Tools (for `swift`, `clang`, `codesign`)

## Install

Download the latest `.dmg` from the
[Releases](https://github.com/facucario/SoundEnhancer/releases) page, open it,
and drag `SoundEnhancer.app` to your Applications folder.

On first launch the app prompts for admin permission to copy the driver to
`/Library/Audio/Plug-Ins/HAL` and restart `coreaudiod`.

## Build from source

```sh
make app          # builds the app + driver (ad-hoc signed, for local use)
make install      # builds and installs to ~/Applications
make run          # build and run from source
make test         # run the Swift tests
```

The `app` target assembles `SoundEnhancer.app` in the repo root, embedding the
driver in `Contents/Resources`.

## Project layout

```
Driver/          C HAL AudioServerPlugIn driver (and its DSP)
Scripts/         build, signing, and notarization scripts
Sources/         SwiftUI menu-bar app
Tests/           DSP unit tests
```

## License

This project is licensed under the GNU General Public License v3.0. See
[LICENSE](LICENSE).

The audio driver in `Driver/` is derived from
[BlackHole](https://github.com/ExistentialAudio/BlackHole), copyright 2019–2026
Existential Audio Inc., and remains under GPL v3. The BlackHole name and branding
are not affiliated with this project.
