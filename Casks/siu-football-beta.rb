cask "siu-football-beta" do
  version "0.1.0-beta.4"
  sha256 "9e8ba0da565b6a478275a6819fe1b2d439f5d860a77da3cac30616321ae1c524"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/SIU-Football-macos26-arm64-beta.4.zip"
  name "SIU Football"
  desc "GameplayFootball LAN test with a SIU lobby"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "SIU Football.app"
end
