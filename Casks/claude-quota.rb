cask "claude-quota" do
  version :latest
  sha256 :no_check

  url "https://github.com/joinnow-io/claude-quota/releases/latest/download/ClaudeQuota.zip"
  name "ClaudeQuota"
  desc "Menu bar app showing Claude Code quota usage in real time"
  homepage "https://github.com/joinnow-io/claude-quota"

  depends_on macos: ">= :sonoma"

  app "ClaudeQuota.app"

  zap trash: [
    "~/Library/Preferences/com.clausequota.app.plist",
  ]
end
