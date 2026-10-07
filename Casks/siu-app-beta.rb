cask "siu-app-beta" do
  version "1.16.0-beta.2"
  sha256 "b738f9f3bc4687ec180e86805373e65510157b06eca9abc00d2102663be551b0"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one and four-player two-a-side LAN football"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
