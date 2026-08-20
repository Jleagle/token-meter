# TokenMeter

macOS menu bar app for tracking AI usage and quotas (Gemini, Claude, OpenAI / Codex).

## Supported models

Only plan/subscription accounts are supported — usage is read from the tools you are already logged into, so no API keys are needed.

| Provider | What is shown | How usage is fetched |
|---|---|---|
| Gemini | Per-model quota bars (5-hour and weekly windows) | Queries the Antigravity language server running locally on your machine (`RetrieveUserQuotaSummary`). Non-Gemini models reported by Antigravity are ignored. |
| Claude (Pro / Max / Team / Enterprise) | 5-hour and weekly limits for your plan | Uses your Claude Code login (macOS Keychain, or `~/.claude/.credentials.json`) to query Anthropic's OAuth usage endpoint. Requires being logged into Claude Code. |
| Codex / OpenAI (Plus / Pro) | 5-hour limit (lowest of the plan's rate-limit windows) | Uses your Codex CLI login (`~/.codex/auth.json`) to query the ChatGPT usage endpoint. Requires being logged into the Codex CLI. |

A provider's section only appears when a logged-in account is found, and the first refresh may show a Keychain permission prompt for the Claude Code credentials — choose "Always Allow" to silence it.

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
