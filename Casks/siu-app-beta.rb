cask "siu-app-beta" do
  version "1.12.0-beta.1"
  sha256 "4f68f285cecddce49378c3268a5ec42da437b2689d061804a310386dfb4058c8"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "LAN football with two-player 11-a-side teams and a shared 3D pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
