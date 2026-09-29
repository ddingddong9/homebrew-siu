cask "siu-football-beta" do
  version "0.1.0-beta.2"
  sha256 "de64669b6986c69ad3b0eae25ef4c720f63802efb081a3184866e2d758b2874c"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/SIU-Football-macos26-arm64-beta.2.zip"
  name "SIU Football"
  desc "GameplayFootball LAN test with a SIU lobby"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "SIU Football.app"
end
