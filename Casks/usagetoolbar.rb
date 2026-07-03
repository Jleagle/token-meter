cask "usagetoolbar" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jleagle/ai-usage-toolbar/releases/download/v#{version}/UsageToolbar.zip"
  name "UsageToolbar"
  desc "macOS menu bar app for tracking AI usage and quotas (Gemini, Claude Pro, Anthropic API)"
  homepage "https://github.com/jleagle/ai-usage-toolbar"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "UsageToolbar.app"

  zap trash: [
    "~/Library/Application Support/UsageToolbar",
    "~/Library/Preferences/com.usage.toolbar.plist",
    "~/Library/Preferences/anthropicApiKey.plist",
    "~/Library/Preferences/monthlyBudget.plist",
    "~/Library/Preferences/openAiApiKey.plist",
    "~/Library/Preferences/openAiMonthlyBudget.plist",
    "~/Library/Preferences/toolbarDisplayModelId.plist",
    "~/Library/Preferences/pollingRateSeconds.plist",
  ]
end
