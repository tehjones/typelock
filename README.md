# TypeLock

TypeLock is a tiny macOS menu bar app that locks an input method to your apps. Set a global default, assign specific input methods to selected apps, and TypeLock restores the right one when macOS or another app changes it.

It is useful when you use multiple keyboard layouts or input methods and want each app, window, or workflow to keep the typing mode you expect.

## Sponsor

TypeLock is sponsored by [Musing Image](https://musingimage.com/).

## Features

- Set a global default input method from the menu bar.
- Assign a specific input method to selected apps.
- Restore the right input method automatically when macOS or another app changes it.
- Exclude apps that should not be managed.
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

TypeLock listens for input source changes, app activation changes, and focused-app changes from macOS Accessibility APIs. When locked, it resolves the active app and applies that app's assigned input method, the global default, or no action for excluded apps.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the implementation notes.

## License

MIT
