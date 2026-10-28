# TokenMeter

macOS menu bar app for tracking AI usage and quotas (Gemini, Claude, OpenAI / Codex).

## Supported models

Only plan/subscription accounts are supported — usage is read from the tools you are already logged into, so no API keys are needed.

| Provider | What is shown | How usage is fetched |
|---|---|---|
| Gemini | Antigravity's shared Gemini quota (5-hour and weekly windows), plus the Gemini 4 Argon weekly quota when your plan has one | Asks the Antigravity language server while the app or `agy` is running. When neither is running, it uses the Google login Antigravity keeps in the macOS Keychain to query Google's Cloud Code API, refreshing the login when it has expired. The non-Gemini pool Antigravity also reports is ignored. |
| Claude (Pro / Max / Team / Enterprise) | 5-hour and weekly limits for your plan, plus any model-scoped weekly limit it reports (e.g. Fable) | Uses your Claude Code login (macOS Keychain, or `~/.claude/.credentials.json`) to query Anthropic's OAuth usage endpoint. An expired session is refreshed and the new token written back, so Claude Code keeps working without signing in again. When Anthropic rate-limits the endpoint, the last values stay on screen with a note until the retry time. |
| Codex / OpenAI (Plus / Pro) | 5-hour limit (lowest of the plan's rate-limit windows) | Uses your Codex CLI login (`~/.codex/auth.json`) to query the ChatGPT usage endpoint. Requires being logged into the Codex CLI. |

A provider's section only appears when its tool is found on the machine. If the tool is installed but not signed in (or the session has expired), a greyed-out card is shown instead of live usage. The first refresh may show a Keychain permission prompt for the Claude Code credentials — choose "Always Allow" to silence it.

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

# Run the unit tests
swift test
```
