# TokenMeter

macOS menu bar app for tracking AI usage and quotas (Gemini, Claude, OpenAI / Codex).

## Installation

```bash
brew install --cask Jleagle/token-meter/token-meter
```

The cask lives in the [Jleagle/homebrew-token-meter](https://github.com/Jleagle/homebrew-token-meter) tap, which that command adds and trusts for you. Each release updates it automatically.

## Usage

Clicking the menu bar icon opens a menu with one line per quota window: the percent left, a bar, and when the window resets. At the bottom, the Settings submenu has "Show Burn Rate Instead" (how fast the window is being used, in place of the percent left) and the Menu Bar submenu picks which window's number appears in the menu bar: Lowest follows the window with the least left (or burning fastest, in burn-rate mode), Latest (the default) follows the window that most recently used quota, a named window pins that one, and None shows the app icon alone. The mark beside the number is the provider it belongs to. The Providers submenu has a check per provider: unchecking one removes its section and stops polling that tool until it is checked again.

Burn rate compares how much of a window's quota you have used with how much of the window's time has passed. 100% means you are on pace to use exactly the whole quota by the time it resets; 200% means twice that pace, so you will run out halfway through; 50% means you will finish with half left. It shows green up to 90%, orange up to 110% and red above that. When a window's reset time is unknown, the percent used is shown instead.

The Claude and Gemini marks in the menu are the Simple Icons versions (CC0); the marks belong to Anthropic and Google.

A provider's section only appears when its tool is found on the machine. If the tool is installed but not signed in (or the session has expired), a greyed-out card is shown instead of live usage. The first refresh may show a Keychain permission prompt for the Claude Code credentials — choose "Always Allow" to silence it.

## Development

Requires Xcode command line tools (macOS 13+).

```bash
# Build and run directly from source (appears in the menu bar)
swift run TokenMeter

# Or build a full .app bundle
./build_app.sh
open ./TokenMeter.app

# Run the unit tests
swift test
```
