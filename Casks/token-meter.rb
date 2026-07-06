cask "token-meter" do
  version "1.2.0"
  sha256 "d018eaefd2e3008f90e84859c3c097158cc1755d5f3b22045c7a94a340742f81"

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
