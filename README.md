# TokenMeter

macOS menu bar app for tracking AI usage and quotas (Gemini, Claude Pro, Anthropic API, OpenAI / Codex).

## Installation

```bash
# 1. Add repository as a Homebrew tap
brew tap jleagle/token-meter https://github.com/jleagle/token-meter

# 2. Trust the tap
brew trust jleagle/token-meter

# 3. Install the application
brew install --cask token-meter
```

## Development

Requires Xcode command line tools (macOS 13+).

```bash
# Build and run directly from source (appears in the menu bar)
swift run TokenMeter

# Or build a full .app bundle
./build_app.sh
open ./TokenMeter.app
```
