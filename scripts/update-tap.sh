#!/bin/bash
set -e

VERSION="$1"
SHA256="$2"
URL="$3"
TAP_GITHUB_TOKEN="$4"

if [ -z "$TAP_GITHUB_TOKEN" ]; then
  echo "TAP_GITHUB_TOKEN not set, skipping tap update"
  exit 0
fi

printf 'cask "claude-quota" do\n' > /tmp/claude-quota.rb
printf '  version "%s"\n' "$VERSION" >> /tmp/claude-quota.rb
printf '  sha256 "%s"\n' "$SHA256" >> /tmp/claude-quota.rb
printf '\n' >> /tmp/claude-quota.rb
printf '  url "%s"\n' "$URL" >> /tmp/claude-quota.rb
printf '  name "ClaudeQuota"\n' >> /tmp/claude-quota.rb
printf '  desc "Menu bar app showing Claude Code quota usage in real time"\n' >> /tmp/claude-quota.rb
printf '  homepage "https://github.com/joinnow-io/claude-quota"\n' >> /tmp/claude-quota.rb
printf '\n' >> /tmp/claude-quota.rb
printf '  depends_on macos: ">= :sonoma"\n' >> /tmp/claude-quota.rb
printf '\n' >> /tmp/claude-quota.rb
printf '  app "ClaudeQuota.app"\n' >> /tmp/claude-quota.rb
printf '\n' >> /tmp/claude-quota.rb
printf '  zap trash: [\n' >> /tmp/claude-quota.rb
printf '    "~/Library/Preferences/com.clausequota.app.plist",\n' >> /tmp/claude-quota.rb
printf '  ]\n' >> /tmp/claude-quota.rb
printf 'end\n' >> /tmp/claude-quota.rb

git clone "https://x-access-token:${TAP_GITHUB_TOKEN}@github.com/joinnow-io/homebrew-tap.git" /tmp/homebrew-tap
mkdir -p /tmp/homebrew-tap/Casks
cp /tmp/claude-quota.rb /tmp/homebrew-tap/Casks/claude-quota.rb
cd /tmp/homebrew-tap
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/claude-quota.rb
git commit -m "Update claude-quota to ${VERSION}" || echo "No changes to commit"
git push
