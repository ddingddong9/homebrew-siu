cask "siu-football-beta" do
  version "0.1.0-beta.1"
  sha256 "9dd56ae571a028cb67e2fe16938f505e167340c6b9a902be7cc6a473c8b176d7"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/gameplayfootball-lan-test-20260929/SIU-Football-macos26-arm64-test.zip"
  name "SIU Football"
  desc "GameplayFootball LAN test with a SIU lobby"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "SIU Football.app"
end
