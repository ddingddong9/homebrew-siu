cask "siu-app-beta" do
  version "1.5.0-beta.1"
  sha256 "3d2ab0c273ca40061767717751b0929e59bdb1755a686f917cc948ec59a1d345"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Football game across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
