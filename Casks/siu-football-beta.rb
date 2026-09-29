cask "siu-football-beta" do
  version "0.1.0-beta.3"
  sha256 "878af9bd6f9bf852938b42a477937ea5ef8c37e2b64712617df7d89a0bc86491"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/SIU-Football-macos26-arm64-beta.3.zip"
  name "SIU Football"
  desc "GameplayFootball LAN test with a SIU lobby"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "SIU Football.app"
end
