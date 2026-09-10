cask "waterbar" do
  version "1.0.0"
  sha256 "6eb87f294be0e338d05e2125ae40dce6d776792fbf0b122f6603502ddf8bba8d"

  url "https://github.com/bmoresca/waterbar/releases/download/v#{version}/WaterBar-#{version}.dmg"
  name "WaterBar"
  desc "Menu bar tracker for the water Claude Code is estimated to drink"
  homepage "https://github.com/bmoresca/waterbar"

  depends_on macos: ">= :ventura"

  app "WaterBar.app"

  # WaterBar is ad-hoc signed - there's no paid Apple Developer membership behind
  # it - so Gatekeeper would refuse to open it after a download. Clearing the
  # quarantine flag here does exactly what right-click -> Open does, minus the
  # dialogs. Delete this block once the app is signed with a Developer ID and
  # notarized; Homebrew's default quarantine handling is the safer behaviour.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/WaterBar.app"],
                   sudo: false
  end

  uninstall quit: "com.betomoresca.waterbar"

  zap trash: [
    "~/.claude/water",
    "~/Library/Preferences/com.betomoresca.waterbar.plist",
  ]
end
