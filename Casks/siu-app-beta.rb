cask "siu-app-beta" do
  version "1.8.0-beta.1"
  sha256 "52d67d3cb92fc7b8aaee485f9e824a465db16457ff76f5bddbad2a66e8ccd1f9"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
