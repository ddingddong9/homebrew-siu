cask "siu-app-beta" do
  version "1.15.0-beta.1"
  sha256 "80a29c5e0b615423ffdd595415e3f9e0e03c85ada5debac2aef33577f55061fd"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one and four-player two-a-side LAN football"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
