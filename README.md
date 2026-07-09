# TypeLock

TypeLock is a tiny macOS menu bar app that locks the current keyboard input source and switches it back when macOS or another app changes it.

It is useful when you use multiple keyboard layouts or input methods and want one app, window, or workflow to stop stealing your typing mode.

## Sponsor

TypeLock is sponsored by [Musing Image](https://musingimage.com/).

## Features

- Lock the current keyboard input source from the menu bar.
- Revert unwanted input source changes automatically.
- Exclude specific apps from the global lock.
- Optionally assign a specific input source per excluded app.
- Launch at login with a local LaunchAgent.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer

TypeLock uses macOS Accessibility APIs to track focus changes. On first launch, macOS may ask you to grant Accessibility permission.

## Build

```sh
swift build
```

## Build The App Bundle

```sh
./bundle.sh
```

This creates `TypeLock.app` in the project directory.

## Install

```sh
cp -R TypeLock.app /Applications/
open /Applications/TypeLock.app
```

## How It Works

TypeLock listens for input source changes, app activation changes, and focused-app changes from macOS Accessibility APIs. When locked, it compares the active context against your exclusions and selects the configured input source when needed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the implementation notes.

## License

MIT
