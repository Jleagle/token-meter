cask "token-meter" do
  version "1.5.0"
  sha256 "c9801b175f357c45fd441fbab78214497b3515dc4280b3488db47c0de24af689"

  url "https://github.com/jleagle/token-meter/releases/download/v#{version}/TokenMeter.zip"
  name "TokenMeter"
  desc "macOS menu bar app for tracking AI usage and quotas (Gemini, Claude Pro, Anthropic API)"
  homepage "https://github.com/jleagle/token-meter"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "TokenMeter.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/TokenMeter.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/TokenMeter",
    "~/Library/Preferences/com.token.meter.plist",
    "~/Library/Preferences/anthropicApiKey.plist",
    "~/Library/Preferences/monthlyBudget.plist",
    "~/Library/Preferences/openAiApiKey.plist",
    "~/Library/Preferences/openAiMonthlyBudget.plist",
    "~/Library/Preferences/toolbarDisplayModelId.plist",
    "~/Library/Preferences/pollingRateSeconds.plist",
  ]
end
