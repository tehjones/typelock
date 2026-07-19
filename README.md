<img width="128px" src="assets/typelock.png" alt="TypeLock icon" />

# TypeLock

TypeLock is a lightweight macOS menu bar app that keeps the right input method active in every app. Choose a global default, add app-specific rules, and TypeLock restores the expected source whenever macOS or another app changes it.

TypeLock works on macOS Ventura 13 or higher.

- [Features](#features)
- [Why TypeLock Exists](#why-typelock-exists)
- [Install](#install)
- [Usage](#usage)
- [App Rules](#app-rules)
- [Development](#development)
- [FAQ](#faq)
- [Sponsors](#sponsors)
- [License](#license)

## Features

- Choose your default input method.
- Choose a different input method for any app that needs one.
- TypeLock switches input methods automatically as you move between apps.
- Lightweight and built for macOS.

## Why TypeLock Exists

I work and study in English almost all the time, but I chat with many of my friends and family in Chinese. So my Mac needs two input methods: ABC for English and a Chinese input method for conversations.

macOS can switch between them, but not in the way I want. There is no simple Shift-only toggle, and the built-in switch feels noticeably slow. Every move between work and chat becomes a small interruption.

WeType gets close to perfect. It lets me type in both Chinese and English, and switch between them with a tap of Shift. That is exactly what I want in chat apps.

But in apps where I only ever type English, the same shortcut becomes a problem. In Ghostty, a stray tap of Shift can switch WeType back to Chinese. Then my next command starts with the wrong characters, and I have to stop, delete them, and switch back.

I built TypeLock to make that impossible. WeType stays as my default for everyday typing, while Ghostty is always locked to ABC. TypeLock switches automatically when I move between apps, so each one is ready for the kind of typing I do there.

## Install

TypeLock currently builds from source. You need Swift 5.9 or newer.

```sh
git clone https://github.com/tehjones/typelock.git
cd typelock
./bundle.sh
cp -R TypeLock.app /Applications/
open /Applications/TypeLock.app
```

## Usage

1. Click the TypeLock icon in the menu bar.
2. Choose an input method, such as **ABC**, as the global default.
3. TypeLock now restores that input method whenever another app or macOS changes it.
4. Open **App Rules…** to configure exceptions or app-specific input methods.

## App Rules

Open **App Rules…**, click **Add App…**, then choose what TypeLock should do in that app.

| Rule | Behavior |
| --- | --- |
| No app rule | Use the global default input method. |
| Specific input method | Override the global default while that app has focus. |
| **Don’t Enforce** | Let the app manage its own input method. |

## Development

See [ARCHITECTURE.md](ARCHITECTURE.md) for implementation details.

Build the executable:

```sh
swift build
```

Build a release app bundle:

```sh
./bundle.sh
```

The bundle is created at `TypeLock.app` in the project directory. By default it
uses an ad-hoc signature, so Accessibility permission must be granted again
after changed builds. Use a stable signing identity to preserve permission:

```sh
TYPELOCK_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./bundle.sh
```

## FAQ

### Why does TypeLock need Accessibility permission?

Some panels accept keyboard input without becoming the frontmost app. Accessibility APIs let TypeLock identify the window or panel that actually owns focus.

### Does TypeLock read my keystrokes?

No. TypeLock reads the focused app and current input-source identifiers. It does not record keystrokes, connect to a server, or send analytics.

### How do I make TypeLock ignore an app?

Open **App Rules…**, add the app, and choose **Don’t Enforce**.

### How do I use a different input method in one app?

Open **App Rules…**, add the app, and select its input method. That choice overrides the global default while the app has focus.

### How do I start TypeLock automatically?

Choose **Launch at Login** from the TypeLock menu.

## Sponsors

TypeLock is sponsored by [EzTranslate](https://eztranslate.com.tw/) and [Musing Image](https://musingimage.com/).

## License

[MIT](./LICENSE)
