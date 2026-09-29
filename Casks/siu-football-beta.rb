cask "siu-football-beta" do
  version "0.1.0-beta.1"
  sha256 "04aefbd6677e41ef98759b3fa36bf7fc9601decb3b40eb3234ac50fd3c2254eb"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/gameplayfootball-lan-test-20260929/SIU-Football-macos26-arm64-test.zip"
  name "SIU Football"
  desc "GameplayFootball LAN test with a SIU lobby"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "SIU Football.app"
end
