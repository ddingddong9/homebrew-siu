cask "siu-app-beta" do
  version "1.6.0-beta.1"
  sha256 "77f01a72f743ab37bcde379690900383d1fc8abdb3afffe16318fbdb22963dc8"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
